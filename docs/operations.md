# Експлуатація RKE2

## HA

Поточний inventory має один server. Для витримування відмови одного server
потрібні три servers із локальним etcd, щонайменше один agent і незалежний
від цих машин відмовостійкий TCP LB. Балансувальник передає TCP 9345 і 6443
на здорові server-вузли без TLS termination. Два servers не дають переваги quorum.

До першого setup:

1. Додайте два чисті server-вузли до `master`; їхні поточні IP не потрібно змінювати.
   Або перерозподіліть наявні чисті машини: перенесіть два записи з `workers` у
   `master`, залишивши їхні імена/IP. Наявні agent-вузли не можна просто
   перейменувати на servers — потрібні drain, видалення вузла та перевстановлення.
2. Першим у `master` залиште master-01-u.k8s. `workers` має містити щонайменше
   один запис. Для запасу ресурсів та рознесення навантаження плануйте більше agents.
3. Створіть незалежний registration endpoint (DNS/IP LB) та перевірте його
   доступність із вузлів і керівного комп'ютера. Його адресу не вигадує playbook.
4. Задайте `rke2_registration_address` адресою цього LB без схеми й порту та
   `rke2_require_ha: true` в group_vars. Endpoint включається до TLS SAN servers.
5. Запустіть setup. Перший server створюється, інші приєднуються по одному,
   потім запускаються agents. Перевірте failover API й застосунків у вікні тесту.

Для HA з уже створеного single-server кластера окремо сплануйте зміну endpoint
і TLS SAN: автоматична зміна чинного конфігу навмисно блокується. Цей playbook
не створює і не тестує сам балансувальник або апаратні failure domains.

## Backup

Локальний розклад — кожні 6 годин, 28 стиснених snapshots на server. Ручний запуск:

```sh
./cluster backup -u ubuntu -K
```

Snapshots за замовчуванням: `/var/lib/rancher/rke2/server/db/snapshots/`.
Для S3 додайте секретні параметри через Ansible Vault, наприклад створіть
`ansible-vault create .local/backup-vault.yml` і збережіть у ньому:

```yaml
rke2_s3:
  etcd-s3: true
  etcd-s3-endpoint: s3.example.internal
  etcd-s3-bucket: YOUR_BUCKET
  etcd-s3-region: us-east-1
  etcd-s3-folder: YOUR_CLUSTER
  etcd-s3-retention: 28
  etcd-s3-access-key: YOUR_ACCESS_KEY
  etcd-s3-secret-key: YOUR_SECRET_KEY
```

Це приклад, не готові credentials. Для першого встановлення:

```sh
./cluster setup -u ubuntu -K -e @.local/backup-vault.yml --ask-vault-pass
./cluster backup -u ubuntu -K
```

S3-параметри записуються в приватний server config; ручний backup читає його.
На наступних setup передавайте той самий Vault-файл. Для ввімкнення S3 на вже
працюючому кластері використовуйте контрольовану зміну config нижче.
Залишайте TLS verification увімкненою; для private CA використовуйте
`etcd-s3-endpoint-ca` та доставте CA-файл на servers. Bucket має мати потрібні
list/get/put/delete дозволи; перевірте uploads і retention реальним тестом.

Окремо збережіть у захищеному offsite-сховищі
`/var/lib/rancher/rke2/server/token` — він потрібен для розшифрування bootstrap
даних при відновленні. Збережіть також Ansible config/Vault, agent secret і
інші операційні ключі. Доступ до snapshot + server token є високопривілейованим.
Копіювання цих секретів playbook автоматично не виконує.

Snapshots etcd не включають PV, зовнішні бази даних та вміст node filesystem.
Для них налаштуйте окремі application-consistent backups і тестуйте їх разом.

## Recovery

Періодично перевіряйте recovery на ізольованих машинах із тими самими версіями
RKE2. Загальний порядок:

1. Виберіть перевірений snapshot, знайдіть відповідний server token і конфігурацію.
2. Зупиніть RKE2 servers перед відновленням; ізолюйте старі peers, щоб вони не
   продовжували писати в попередній кластер. Не запускайте setup як recovery.
3. Відновіть перший server з snapshot через `rke2 server --cluster-reset`
   та `--cluster-reset-restore-path`, використовуючи оригінальний server token.
   Для нової машини відновіть token до запуску; для local snapshot при
   налаштованому S3 використовуйте відповідний параметр відключення S3.
4. За офіційною процедурою відновлення multi-server видаліть старі etcd DB
   **лише на інших зупинених peers**, потім приєднайте їх до відновленого server.
5. Перевірте quorum, API, nodes, workloads, секрети та дані застосунків.
   Відновіть PV/application backups і перевірте записи/читання перед поверненням трафіку.

Точні команди залежать від місця snapshot і втрат вузлів — використовуйте
[офіційну процедуру для вашого випадку](https://docs.rke2.io/datastore/backup_restore).
Руйнівне відновлення навмисно не приховане за командою setup.

## Оновлення та зміна config

Setup відмовляється змінювати встановлену версію або існуючий config.
Це захищає від неконтрольованого restart робочого кластера. Для upgrade:

1. Перевірте release notes, сумісність API/операторів, допустимий version skew
   та порядок переходу; не пропускайте minor-версії. Пройдіть staging.
2. Зробіть snapshot, перевірте offsite backup, token і план recovery.
3. Виберіть точний новий release tag, отримайте installer із цього tag,
   перевірте його SHA-256 через довірений канал, оновіть version/checksum у Git.
4. Оновлюйте servers по одному, потім agents по одному. На кожному вузлі
   виконайте cordon/drain з урахуванням PDB та локальних даних, встановіть
   release через перевірений installer із `INSTALL_RKE2_VERSION` і відповідним
   `INSTALL_RKE2_TYPE=server` або `agent`, перезапустіть лише його RKE2 service.
5. Дочекайтеся Ready, справності etcd/API та workloads; виконайте uncordon,
   лише потім переходьте до наступного вузла. Для single-server це downtime API.
6. Після вирівнювання всіх версій повторіть setup як перевірку відповідності.
   Просте повернення старого binary не є безпечним rollback datastore.

Для зміни server/agent config: перегляньте diff без розкриття токенів, зробіть
backup, синхронізуйте критичні параметри на servers, виконайте контрольований
restart по одному з перевіркою стану. Потім узгодьте group_vars/template і
повторіть setup. Зміна мережевих CIDR чи ролі вузла потребує окремого плану.

`ubuntu-update.yml` оновлює тільки пакети ОС, не RKE2, і не перезавантажує вузли
автоматично. Плануйте оновлення ОС, drain і reboot окремо.

## Діагностика

На server: `sudo journalctl -u rke2-server -n 100 --no-pager`.
На agent: `sudo journalctl -u rke2-agent -n 100 --no-pager`.
Kubectl на server: `/var/lib/rancher/rke2/bin/kubectl` із
`--kubeconfig=/etc/rancher/rke2/rke2.yaml`.

Перевіряйте failed pods/HelmChart jobs, ресурси, час, порти 9345/6443 та
мережеві політики. Не видаляйте DB і не запускайте uninstall для виправлення
звичайної помилки підключення. Для CIS-профілю потрібна окрема host/security
конфігурація та аудит за [hardening guide](https://docs.rke2.io/security/hardening_guide).
