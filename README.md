# Kubernetes: домашній навчальний кластер

Ansible розгортає один control plane та три worker-вузли на чистій
**Ubuntu Server 22.04 або 24.04 LTS** із systemd. Jenkins — необов'язковий:
увесь кластер можна встановити однією командою з керівного комп'ютера.

## Адреси та вимоги

Поточні імена вузлів у `kube-cluster/hosts-ubuntu` збережені:

| Роль | Ім'я | IP |
| --- | --- | --- |
| Control plane | master-01-u.k8s | 192.168.1.95 |
| Worker | worker-01-u.k8s | поточна адреса через DNS або /etc/hosts |
| Worker | worker-02-u.k8s | поточна адреса через DNS або /etc/hosts |
| Worker | worker-03-u.k8s | поточна адреса через DNS або /etc/hosts |

Числових IP workers у репозиторії немає. Збережіть їхні наявні адреси;
налаштуйте DNS або `/etc/hosts` на керівному комп'ютері, або вкажіть ці ж
адреси як `ansible_host` в inventory. Playbook не змінює IP, Netplan чи DNS.
Кожен вузол повинен мати унікальні hostname, MAC і product UUID; master —
щонайменше 2 CPU та 2 GiB RAM. Мережа pod `10.244.0.0/16` не повинна
перетинатися з мережею машин, VPN чи мережею сервісів `10.96.0.0/12`.

Потрібні:

- OpenSSH server на кожному вузлі та користувач із доступом `sudo`.
  Якщо SSH не встановлено, виконайте через консоль вузла:
  `sudo apt-get update && sudo apt-get install -y openssh-server` і
  `sudo systemctl enable --now ssh`.
- SSH-ключ керівного комп'ютера в `~/.ssh/authorized_keys` користувача вузла.
  Перевірте fingerprint і SSH-з'єднання перед запуском Ansible.
- Доступ вузлів до Ubuntu APT, pkgs.k8s.io, GitHub та реєстрів образів
  (registry.k8s.io, ghcr.io, docker.io); робочі DNS і синхронізація часу.
- Між вузлами: TCP 6443 до master, TCP 10250 для kubelet, UDP 8472 для
  Flannel VXLAN. На master також TCP 2379–2380 для etcd і локальні
  10257/10259; NodePort 30000–32767 потрібні лише для відповідних сервісів.
  Налаштуйте наявний firewall під свою мережу до запуску; playbook його не вимикає.

На керівному комп'ютері потрібен `ansible-core` 2.16 або новіший. Наприклад,
на Ubuntu 24.04: `sudo apt-get install -y ansible`. На вузлах Python, containerd,
kubeadm, kubelet та kubectl встановлюються автоматично. Docker, NFS, Jenkins,
Java та Zabbix для створення кластера не потрібні.

## Запуск із кореня репозиторію

Вкажіть реального користувача, створеного під час встановлення Ubuntu
(у прикладах — `ubuntu`). Inventory більше не вимагає входу як root.

```sh
ansible-inventory -i kube-cluster/hosts-ubuntu --graph
ansible-playbook -i kube-cluster/hosts-ubuntu kube-cluster/ansible-playbook/cluster.yml --syntax-check
ansible-playbook -i kube-cluster/hosts-ubuntu kube-cluster/ansible-playbook/cluster.yml -u ubuntu --become --ask-become-pass
```

Якщо sudo не потребує пароля, приберіть `--ask-become-pass`. Для іншого ключа
додайте `--private-key ~/.ssh/your_key`. Перший запуск потребує всього inventory:
не обмежуйте його лише workers, оскільки join-команда генерується на master.

Сценарій встановлює Python за потреби, вимикає swap у поточній сесії та fstab,
завантажує модулі ядра, налаштовує forwarding і containerd із systemd cgroups,
встановлює компоненти Kubernetes із репозиторію конкретної minor-версії та
ставить їх на hold. Далі виконує `kubeadm init`, встановлює Flannel, приєднує
workers і очікує Ready всіх вузлів та готовність CoreDNS.

Параметри містяться в `kube-cluster/group_vars/all.yml`: Kubernetes `v1.36`,
Flannel `v0.28.10`, початковий IP master та pod CIDR. Пакети отримують доступний
patch-реліз вибраної minor-гілки під час першого встановлення. Це сценарій
створення кластера, а не оновлення його версії: зміна minor-параметра не виконує
`kubeadm upgrade` і не оновлює пакети на hold.

Повторний запуск пропускає init/join за файлами конфігурації, але знову
застосовує системні налаштування та Flannel. Автоматичного `kubeadm reset`
немає. Частково невдалий init/join потребує перевірки стану адміністратором.
Join-токен діє 15 хвилин, прихований у логах та не записується на NFS.
Адміністраторський kubeconfig залишається тільки на master з правами `0600`.

## Перевірка після встановлення

```sh
ssh ubuntu@master-01-u.k8s 'sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide'
ssh ubuntu@master-01-u.k8s 'sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A'
```

Для kubectl на власному комп'ютері отримайте `/etc/kubernetes/admin.conf`
через захищене SSH-з'єднання та збережіть із правами `0600`. Цей файл дає
повний адміністративний доступ; не розміщуйте його в Git чи спільному NFS.

## Jenkins та старі приклади

`kube-cluster/jenkins-jobs/K8S_create_cluster.jenkins` запускає той самий
`cluster.yml` на агенті `controller`. На агенті заздалегідь налаштуйте Ansible,
SSH-ключ, known_hosts, користувача (`ANSIBLE_REMOTE_USER`) та sudo без
інтерактивного пароля або через захищені Jenkins credentials.

Окремі `master.yml` і `workers.yml` можна запускати після підготовки вузлів;
`workers.yml` сам отримує новий join-токен з master. Старе ім'я
`install_docker_ubuntu.yml` залишено як сумісний вхід до підготовки containerd.

`deployments/` та `service-mesh/` містять окремі навчальні приклади застосунків,
HPA та mesh. Вони не встановлюються разом із кластером; HPA потребує metrics-server,
а сервіс типу LoadBalancer на bare metal — окремого балансувальника.
Старі CentOS, NFS, Dashboard, cleanup і допоміжні Jenkins jobs залишені як
історичні приклади та не входять до перевіреного Ubuntu-сценарію.
Cleanup-playbook-и руйнівні: не запускайте їх для звичайного повторного встановлення.

Налаштування звірено з [інструкцією kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/),
[вимогами до runtime](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
і [релізом Flannel](https://github.com/flannel-io/flannel/releases/tag/v0.28.10).
