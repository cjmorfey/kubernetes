# Kubernetes на чистій Ubuntu

Домашній навчальний кластер: **один master і три workers**, встановлення з
керівного комп'ютера однією командою. Підтримуються чисті **Ubuntu Server
22.04 / 24.04 LTS** із systemd. IP машин залишаються поточними.

```sh
./cluster setup -u ubuntu -K
```

`ubuntu` замініть на користувача, створеного під час встановлення ОС.
`-K` запитує пароль sudo; для sudo без пароля цей параметр не потрібен.

## Перед першим запуском

1. На керівному комп'ютері встановіть `ansible-core` 2.16 або новіший і Git.
   Наприклад, на Ubuntu 24.04: `sudo apt-get update && sudo apt-get install -y ansible git`.
   Клонуйте цей репозиторій і перейдіть до його кореня. Команду запускають на
   керівному комп'ютері, який має SSH-доступ до всіх вузлів, а не на кожному вузлі.
2. На кожній машині під час встановлення Ubuntu увімкніть OpenSSH server і
   створіть користувача із sudo. Якщо SSH відсутній, через консоль виконайте
   `sudo apt-get update && sudo apt-get install -y openssh-server` та
   `sudo systemctl enable --now ssh`.
3. Додайте свій SSH-ключ до `~/.ssh/authorized_keys` цього користувача на вузлах.
   Перевірте fingerprint і перше SSH-з'єднання до кожної адреси з inventory.
   Для входу за паролем додайте `--ask-pass` (може знадобитися `sshpass` на controller).
4. Перевірте адреси в [inventory](kube-cluster/hosts-ubuntu). Власник мережі має
   забезпечити постійні IP через DHCP reservation або налаштування Ubuntu.
   Сценарій не редагує Netplan, IP чи DNS.

| Роль | Ім'я вузла в Kubernetes | Адреса SSH |
| --- | --- | --- |
| Master | master-01-u.k8s | **192.168.1.95** |
| Worker | worker-01-u.k8s | worker-01-u.k8s |
| Worker | worker-02-u.k8s | worker-02-u.k8s |
| Worker | worker-03-u.k8s | worker-03-u.k8s |

Числових IP workers у старому проєкті немає. Залиште їхні імена в DNS або
`/etc/hosts` керівного комп'ютера. Або вкажіть їхні **наявні** IP у
`ansible_host` — вигадувати нові адреси не потрібно. Ubuntu-вузлам не потрібно
вміти розв'язувати ці приватні DNS-імена: для кластерних адрес використовуються IP.

Для машин із кількома інтерфейсами вкажіть `cluster_node_ip` в inventory:

```ini
worker-01-u.k8s ansible_host=worker-01-u.k8s cluster_node_ip=<наявний-LAN-IP>
```

За замовчуванням використовується числовий `ansible_host` або IPv4 інтерфейсу
з default route. Вибрана адреса має бути призначена цьому вузлу; сценарій
задає її kubelet, але не змінює мережеві налаштування ОС. Імена Kubernetes
задаються через `--node-name`, тому стандартні hostname чистих ОС не створюють
однакових імен вузлів. Клоновані машини повинні мати унікальні machine-id, MAC і UUID.

## Вимоги до машин та мережі

- Щонайменше 2 GiB RAM на вузол; master — мінімум 2 vCPU. Для застосунків
  потрібні додаткові ресурси й місце на диску.
- Ubuntu APT, pkgs.k8s.io, GitHub і реєстри образів (registry.k8s.io,
  ghcr.io, docker.io) мають бути доступні з вузлів; потрібні DNS і правильний час.
- Між вузлами дозволені TCP 6443 до master, TCP 10250 та UDP 8472 для Flannel.
  На master etcd використовує TCP 2379–2380, локальні компоненти — 10257/10259.
  NodePort TCP/UDP 30000–32767 відкривайте лише для сервісів, що його використовують.
- Якщо UFW/інший firewall активний, налаштуйте також forwarding і pod-трафік
  між вузлами. Сценарій повідомляє про активний UFW і зберігає ваші правила.
- Pod CIDR `10.244.0.0/16` і service CIDR `10.96.0.0/12` мають не перетинатися
  між собою, з LAN або VPN. Змінюйте їх до першого встановлення.

## Чотири команди

```sh
# Локальна перевірка inventory та синтаксису, без SSH і змін машин
./cluster check

# Повна підготовка чистих вузлів, створення та перевірка кластера
./cluster setup -u ubuntu -K

# Вузли та pods у всіх namespaces
./cluster status -u ubuntu -K

# Отримати admin kubeconfig локально
./cluster kubeconfig -u ubuntu -K
KUBECONFIG="$PWD/.local/kubeconfig" kubectl get nodes -o wide
```

Ключ можна передати через `--private-key ~/.ssh/lab`. Для іншого inventory:
`CLUSTER_INVENTORY=/path/to/hosts ./cluster setup -u ubuntu -K`.
Воно повинне містити `master`, `workers` і спільну групу `k8s:children`.
Параметри проєкту лежать у `kube-cluster/group_vars/all.yml`; для власного
inventory скопіюйте поруч каталог `group_vars` або передайте цей файл через
`-e @kube-cluster/group_vars/all.yml`.

Запускайте setup із повним inventory без `--limit`: спочатку перевіряються
всі машини, потім створюється master і приєднуються workers. Щоб додати чистий
worker, додайте його в inventory і повторіть ту саму команду setup.

Kubeconfig записується в `.local/kubeconfig` у приватному каталозі `0700`, файл
має права `0600`, каталог виключений із Git. Він дає повний адміністративний
доступ. Команда не перезаписує ваш `~/.kube/config`.

## Як влаштоване встановлення

Залишено стандартний **kubeadm + containerd + Flannel**. Це звичайний Kubernetes,
придатний для вивчення його компонентів. Jenkins, Docker Engine, NFS, Java та
Zabbix більше не є залежностями встановлення. Python на чистих вузлах
встановлюється автоматично; Ansible потрібен лише на керівному комп'ютері.

Сценарій послідовно виконує:

1. Перевірку inventory, Ubuntu, sudo, ресурсів, IP та machine-id.
2. Встановлення залежностей, вимкнення swap у сесії та fstab, завантаження
   модулів ядра, налаштування forwarding і containerd із systemd cgroups.
3. Встановлення однакових версій kubeadm/kubelet/kubectl на всіх вузлах і hold пакетів.
4. `kubeadm init` з явними версією, IP, ім'ям вузла та CIDR; перевірку API.
5. Встановлення Flannel із конкретного релізу та приєднання чистих workers.
6. Очікування **кожного імені з inventory**, Flannel і CoreDNS та показ результату.

Початкові параметри: Kubernetes `v1.36`, Flannel `v0.28.10`.
За першого встановлення вибирається один доступний patch-реліз Kubernetes,
а всі вузли отримують саме його. На повторних запусках і під час додавання
workers використовується версія master. Для повністю відтворюваного першого
встановлення задайте точну Debian-версію в `kubernetes_package_version`.

Сценарій керує `/etc/containerd/config.toml` і `/etc/default/kubelet`.
Повторний запуск не скидає кластер, не виконує автоматичних upgrade/downgrade
Kubernetes і не генерує join-токен, якщо всі workers уже приєднані. Новий токен
діє 15 хвилин, прихований у логах, зберігається в пам'яті Ansible та відкликається
після спроб приєднання. При втраті SSH TTL обмежує термін його дії.

Зміна minor-версії, CIDR або імен на вже створеному кластері потребує окремого
плану міграції. Це не HA-кластер: один master є єдиною точкою відмови.

## Обслуговування та помилки

За невдалого запуску прочитайте помилку і виправте доступ, репозиторій чи мережу,
після чого повторіть setup. Частково виконаний init/join може залишити конфігурацію;
наявність файлів сама по собі не означає успіху — фінальна перевірка API та вузлів
виявить проблему. Корисні команди на вузлі:

```sh
sudo journalctl -u containerd -u kubelet -n 100 --no-pager
sudo systemctl status containerd kubelet
```

Оновлення Ubuntu — окремий `ubuntu-update.yml`: він поважає hold Kubernetes
і повідомляє про потребу reboot через `/var/run/reboot-required`, без автоматичного
перезавантаження активного кластера. Перед reboot виконайте drain вузла.

Для навмисного повного видалення стану кластера є окремий сценарій:

```sh
ansible-playbook kube-cluster/ansible-playbook/clean_k8s_ubuntu.yml -u ubuntu -K -e confirm_cluster_reset=true
```

Він виконує `kubeadm reset`, видаляє CNI-конфігурацію, credentials та etcd-дані.
Після reset перезавантажте вузли перед новим setup. Загальні iptables-правила
не очищуються. Без `confirm_cluster_reset=true` сценарій зупиняється до змін.

## Jenkins, приклади та перевірки

Основний Jenkins pipeline — `kube-cluster/jenkins-jobs/K8S_create_cluster.jenkins`;
він викликає ті самі `./cluster check` та `./cluster setup`. На агенті `controller`
налаштуйте Ansible, known_hosts, SSH-ключ і sudo; користувача можна задати через
`ANSIBLE_REMOTE_USER`. Окрема job підготовки встановлює залежності. Сумісні jobs master/workers також
викликають повний setup, щоб працювати з чистими машинами.

Застарілі CentOS, Docker/NFS, Java 8, Dashboard та допоміжні jobs перенесено в
[legacy/](legacy/README.md). Вимкніть старі Jenkins jobs, що використовують їхні
колишні шляхи. Навчальні `deployments/` і `service-mesh/` встановлюються окремо;
HPA потребує metrics-server, bare-metal LoadBalancer — реалізації на кшталт MetalLB.

```sh
./scripts/check.sh
```

Перевірки охоплюють синтаксис підтримуваних playbook-ів, shell та локальний
тест справжнього worker-playbook з підставним kubeadm: успішні joins і відкликання
токена після помилки. GitHub Actions запускає їх на Ubuntu. Вони не замінюють
інтеграційного встановлення на справжніх Ubuntu VM.

Джерела: [створення кластера kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/),
[container runtime і cgroups](https://kubernetes.io/docs/setup/production-environment/container-runtimes/),
[Flannel v0.28.10](https://github.com/flannel-io/flannel/releases/tag/v0.28.10).
