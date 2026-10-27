# Kubernetes на RKE2

Встановлення **RKE2 на чисті Ubuntu Server 22.04 / 24.04 LTS** через Ansible.
RKE2 керує Kubernetes, власним containerd, etcd, Canal, CoreDNS, metrics-server
і Traefik як єдиним дистрибутивом. Kubeadm, окремий Docker/containerd та NFS
для встановлення більше не використовуються.

```sh
./cluster setup -u ubuntu -K
```

Це **створення нового кластера**, а не оновлення kubeadm-кластера на місці.
Старий Kubernetes на вузлі спричиняє зупинку до встановлення RKE2.
Для перенесення застосунків і даних дивіться [план міграції](docs/migration.md).

## Поточні машини та доступність

Імена, наявні IP та початкові ролі збережено в [inventory](kube-cluster/hosts-ubuntu):

| Група Ansible | Машина | SSH-адреса | Роль RKE2 |
| --- | --- | --- | --- |
| master | master-01-u.k8s | 192.168.1.95 | server: control plane + etcd |
| workers | worker-01-u.k8s | worker-01-u.k8s | agent |
| workers | worker-02-u.k8s | worker-02-u.k8s | agent |
| workers | worker-03-u.k8s | worker-03-u.k8s | agent |

**Один server залишається єдиною точкою відмови.** Заміна дистрибутива сама
по собі не робить цю топологію HA. Вона придатна, якщо допустима зупинка та
відновлення з backup. Для роботи з вимогою безперервності потрібні **три server,
щонайменше один agent та окремий відмовостійкий TCP-балансувальник**.
Інсталяція підтримує 1, 3 або 5 servers; інструкція — [HA](docs/operations.md#ha).

Числових IP workers у проєкті немає: збережіть поточний DNS або `/etc/hosts`
керівного комп'ютера, або задайте їхні наявні адреси в `ansible_host`.
Сценарій не змінює Netplan, IP, DNS чи firewall. За кількох мережевих карт
задайте `cluster_node_ip` у рядку вузла; інакше використовується числовий
`ansible_host` або IPv4 інтерфейсу з default route. Ім'я вузла задається з inventory.

## Перед запуском

1. На керівному комп'ютері потрібні Git та `ansible-core >= 2.16`.
   Наприклад, для Ubuntu 24.04: `sudo apt-get update && sudo apt-get install -y ansible git`.
   Клонуйте репозиторій і перейдіть у його корінь.
2. На вузлах увімкніть OpenSSH server та користувача із sudo під час встановлення Ubuntu.
   Якщо SSH відсутній, через консоль: `sudo apt-get install -y openssh-server`,
   `sudo systemctl enable --now ssh`.
3. Додайте SSH-ключ керівного комп'ютера до `~/.ssh/authorized_keys` користувача
   вузла. Перевірте fingerprint та SSH-з'єднання до кожної адреси з inventory.
   `ubuntu` у прикладах замініть на свого користувача; `-K` запитує пароль sudo.
4. Виділіть мінімум 4 GiB RAM на кожен вузол, 2 vCPU на server; для робочого
   навантаження плануйте запас, SSD для etcd і достатній диск для образів та logs.
   Кожна машина має мати унікальні IP, machine-id, MAC і UUID.
5. Перевірте DNS, час і вихідний HTTPS до Ubuntu APT, raw.githubusercontent.com,
   GitHub release assets та реєстрів образів RKE2, зокрема docker.io.

Мережа між вузлами:

| Порт | Доступ |
| --- | --- |
| TCP 9345, 6443 | усі вузли → servers / registration LB |
| TCP 2379–2381 | між servers для etcd |
| TCP 10250, 9099; UDP 8472 | між вузлами: kubelet, Canal health, VXLAN |
| TCP 80, 443 | клієнти → ingress за вашою схемою публікації |
| TCP/UDP 30000–32767 | лише якщо використовуєте NodePort |

Дозвольте forwarding і pod-трафік у власному firewall; VXLAN та etcd повинні
залишатися у приватній мережі. Pod `10.244.0.0/16`, services `10.96.0.0/12`
і DNS `10.96.0.10` не повинні конфліктувати з LAN/VPN. Вибирайте мережі до init.

## Команди

```sh
./cluster check                         # локально, без SSH та змін машин
./cluster setup -u ubuntu -K            # підготовка, RKE2 servers/agents, перевірка
./cluster status -u ubuntu -K           # nodes та pods
./cluster kubeconfig -u ubuntu -K       # приватний admin kubeconfig
KUBECONFIG="$PWD/.local/kubeconfig" kubectl get nodes -o wide
./cluster backup -u ubuntu -K           # snapshot etcd на першому server, також S3 якщо налаштовано
```

Для іншого ключа додайте `--private-key ~/.ssh/lab`. Для іншого inventory:
`CLUSTER_INVENTORY=/path/to/hosts ./cluster setup -u ubuntu -K`.
Inventory має групи `master`, `workers`, `k8s:children`; скопіюйте поруч
`group_vars` або передайте `-e @kube-cluster/group_vars/all.yml`.
Перший запис групи `master` — bootstrap server; зберігайте його порядок.
Setup запускається для повного inventory без `--limit`.

Параметри — [group_vars/all.yml](kube-cluster/group_vars/all.yml):
зафіксовано `v1.37.1+rke2r1` та SHA-256 installer-а з того самого release tag.
Сам installer перевіряє checksum release artifact. Немає вибору рухомого
`stable/latest` під час встановлення. Версія однакова на всіх вузлах.

Ansible встановлює Python за потреби, системні залежності й AppArmor tools,
налаштовує swap, модулі та forwarding, потім встановлює RKE2. Перший server
запускається перед іншими; решта servers і agents приєднуються послідовно.
Servers мають taint, щоб звичайні застосунки працювали на agents.
Перевірка очікує кожен вузол з inventory, Canal і CoreDNS.

`setup` не скидає кластер і не виконує автоматичних upgrade/downgrade або
перезапусків через зміну конфігурації. Інша версія, зміна ролі або відмінний
наявний конфіг зупиняють виконання: використовуйте [операційні процедури](docs/operations.md).
Щоб додати чистий agent, додайте його в inventory і повторіть setup.
Не встановлюйте паралельно системні kubelet чи containerd.

## Credentials, backups і експлуатація

Конфіг `/etc/rancher/rke2/config.yaml` має права `0600`, каталог — `0700`.
Server- і agent-токени розділені, передаються через Ansible в пам'яті й приховані
в логах. RKE2 зберігає їх на вузлах для запуску та повторних приєднань;
це постійні credentials, а не короткочасні kubeadm-токени.
Не використовуйте `--diff` для роботи із секретами.

Admin kubeconfig зберігається у `.local/kubeconfig` з правами `0600`; адреса
`127.0.0.1` замінюється на registration endpoint із TLS SAN. `.local/` виключено
з Git. Для повсякденної роботи створіть окремі RBAC-доступи замість admin.

Snapshots etcd створюються кожні 6 годин, стискаються, зберігаються 28 локальних
копій на кожному server. **Локальні snapshots не захищають від втрати машини.**
До розміщення важливих даних налаштуйте offsite S3 або зовнішнє копіювання,
збережіть server token і проведіть тест відновлення. etcd snapshot не містить
даних PersistentVolume. Інструкції: [backup, recovery, upgrade](docs/operations.md).

RKE2 надає базові компоненти, але ваші SLA також потребують сховища для PV,
backup даних застосунків, моніторингу, alerting, політик доступу й TLS для сервісів.
Ingress — Traefik; bare-metal `LoadBalancer` потребує окремої реалізації.
Ця конфігурація не заявляє проходження CIS-аудиту.

## Jenkins і перевірки

`kube-cluster/jenkins-jobs/K8S_create_cluster.jenkins` запускає ті самі команди.
На агенті `controller` налаштуйте Ansible, SSH/known_hosts і sudo; користувача
можна задати через `ANSIBLE_REMOTE_USER`. Інші підтримувані jobs теж запускають setup.

```sh
./scripts/check.sh
```

Перевіряються shell, синтаксис playbook-ів і рендер реального конфігу для
bootstrap server, додаткових servers та agent: різні credentials, мережі й snapshots.
GitHub Actions виконує ті самі перевірки. Встановлення та HA failover на реальних
Ubuntu VM цими локальними тестами не перевіряються.

Старий kubeadm-сценарій — [legacy/kubeadm](legacy/kubeadm/README.md), інші історичні
сценарії — [legacy](legacy/README.md); вони не входять до активного встановлення.
`deployments/` і `service-mesh/` — окремі приклади, автоматично не розгортаються.

Офіційні джерела: [RKE2 Quick Start](https://docs.rke2.io/install/quickstart),
[HA](https://docs.rke2.io/install/ha), [network requirements](https://docs.rke2.io/install/requirements),
[backup/restore](https://docs.rke2.io/datastore/backup_restore),
[зафіксований release](https://github.com/rancher/rke2/releases/tag/v1.37.1%2Brke2r1).
