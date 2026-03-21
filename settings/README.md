# Settings (Private Configuration)

โฟลเดอร์นี้เก็บ config ส่วนตัวทั้งหมด — gitignored ทั้งหมดยกเว้น `*.env.example` และไฟล์นี้

## Setup เริ่มต้น

Copy ทุกไฟล์ `.example` แล้วแก้ค่าจริง:

```bash
cp settings/jumphost.env.example    settings/jumphost.env
cp settings/git.env.example         settings/git.env
cp settings/openstack.env.example   settings/openstack.env
cp settings/openrc.env.example      settings/openrc.env
cp settings/credentials.env.example settings/credentials.env
```

## ไฟล์และความหมาย

| ไฟล์ | แก้เมื่อ |
|------|---------|
| `jumphost.env` | เปลี่ยน jumphost IP / user / port / branch |
| `git.env` | เปลี่ยน git repo URL หรือ branch |
| `openstack.env` | เปลี่ยน network / flavor / project |
| `openrc.env` | เปลี่ยน path ของ openrc บน jumphost |
| `credentials.env` | เปลี่ยน root password / key ของ VM |

## ตารางสรุป "แก้อะไร ไปที่ไหน"

| อยากแก้อะไร | ไฟล์ที่ต้องแก้ |
|-------------|--------------|
| jumphost IP/user/port | `settings/jumphost.env` |
| git URL/branch | `settings/git.env` |
| openstack network/flavor | `settings/openstack.env` |
| path ของ openrc | `settings/openrc.env` |
| root password VM | `settings/credentials.env` |
| mirror ubuntu 18.04 | `config/guest/ubuntu-18.04.env` |
| mirror ubuntu 24.04 | `config/guest/ubuntu-24.04.env` |
| เพิ่ม ubuntu version ใหม่ | สร้าง `config/os/ubuntu/<version>.env` |
| policy publish image | `config/pipeline/publish.env` |
| policy clean VM | `config/pipeline/clean.env` |
