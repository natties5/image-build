## Pipeline ที่ควรเป็น

ลำดับที่ผมแนะนำคือแบบนี้:

### Phase 0 — Auth / Preflight

เช็กก่อนว่า OpenStack ใช้งานได้จริงและ resource naming/policy ถูกต้อง

สิ่งที่ควรทำ:

* source `openrc`
* เช็ก token ใช้งานได้
* เช็ก project ที่กำลังอยู่
* เช็ก image/server/volume ที่มีอยู่แล้วตาม prefix
* validate config จำเป็น เช่น project, naming templates, policy ต่าง ๆ

คำสั่งที่ใช้อยู่ตอนนี้:

* `openstack token issue`
* `openstack project show`
* `openstack image list`
* `openstack server list`
* `openstack volume list` 

จุดที่ต้องดัก:

* `openrc` ไม่มีหรือ source ไม่ได้
* token issue ไม่ผ่าน
* project ไม่ตรง
* naming template malformed
* resource prefix ไม่ตรง

---

### Phase 1 — Sync / Discover Base Image

ยังไม่แตะ OpenStack มาก แค่ resolve ว่า image source ที่จะใช้คืออะไร

สิ่งที่ควรได้:

* version
* local path
* checksum
* artifact URL
* release page
* format ที่ตรวจได้

ผลลัพธ์นี้จะเป็น input ให้ phase import base image ต่อ

---

### Phase 2 — Import Base Image to Glance

เอาไฟล์ image ที่โหลดมาแล้ว import เข้า Glance เป็น “base image”

ลำดับงาน:

1. เช็กว่ามี summary/manifests จาก sync phase แล้ว
2. หา local image path ของ version ที่ต้องการ
3. ใช้ `qemu-img info` ตรวจ format
4. เช็กว่ามี base image ชื่อนี้ใน Glance แล้วหรือยัง
5. จัดการตาม policy:

   * `error`
   * `skip`
   * `replace`
6. ถ้ายังไม่มีหรือ replace แล้ว:

   * create image
   * set properties/tags
   * wait จน `active`
7. เขียน manifest ของ base image

คำสั่งที่ใช้อยู่ตอนนี้:

* `qemu-img info`
* `openstack image list --name ...`
* `openstack image create ... --file ... --disk-format ... --container-format bare`
* `openstack image set --tag ...`
* `openstack image show ... -c status`
* `openstack image delete ...` 

สิ่งที่ต้องดัก:

* local image file ไม่มี
* format ไม่ใช่ `qcow2` หรือ `raw`
* image ชื่อซ้ำ
* image ติดสถานะ `killed/deleted/deactivated`
* รอนานเกิน timeout

สิ่งที่ “บางอันไม่ได้ทำ” ต้องทำยังไง:

* ถ้ามี base image อยู่แล้ว:

  * ถ้า policy = `skip` → ใช้ของเดิมต่อ
  * ถ้า policy = `replace` → ลบแล้วสร้างใหม่
  * ถ้า policy = `error` → fail ทันที 

สิ่งที่ “บางอันนาน” ต้องทำยังไง:

* image import บาง cloud ช้า ต้อง poll status
* ต้องมี timeout
* ถ้า timeout ให้ fail พร้อม status ล่าสุด ไม่ค้างเงียบ ๆ 

---

### Phase 3 — Create Boot Volume from Base Image

เอา base image ใน Glance มาสร้าง boot volume

นี่เป็นขั้นที่คุณเรียกว่า `create volume`

ลำดับงาน:

1. อ่าน manifest ของ base image
2. เช็กว่า `BASE_IMAGE_ID` มีจริง
3. สร้าง volume จาก image
4. รอจน volume เป็น `available`

คำสั่งที่ใช้อยู่ตอนนี้:

* `openstack volume create --image ... --size ... --type ...`
* `openstack volume show ... -c status` 

สิ่งที่ต้องดัก:

* `BASE_IMAGE_ID` ไม่มี
* volume type/config ไม่ครบ
* volume เข้าสถานะ error
* timeout ตอนรอ `available`

สิ่งที่นาน:

* การ clone volume จาก image บาง cloud ใช้เวลานานมาก
* ต้องมี loop รอสถานะและ timeout แยกของ volume โดยเฉพาะ 

---

### Phase 4 — Create VM from Volume

สร้าง VM จาก boot volume ที่เพิ่งได้มา

นี่คือขั้น `create vm from volume`

ลำดับงาน:

1. เช็กว่า volume พร้อมแล้ว
2. ประกอบชื่อ VM และชื่อ volume ตาม template
3. ป้องกันชื่อซ้ำ
4. สร้าง cloud-init/user-data ตาม policy ของ guest access
5. สร้าง server จาก volume
6. รอจน server เป็น `ACTIVE`
7. ถ้าต้องใช้ floating IP:

   * ใช้ IP ที่มีอยู่แล้ว หรือ
   * allocate ใหม่
8. เก็บข้อมูล output เช่น server id, volume id, login ip

คำสั่งที่ใช้อยู่ตอนนี้:

* `openstack server show ...`
* `openstack volume show ...`
* `openstack server create --flavor ... --network ... --security-group ... --volume ... --user-data ...`
* `openstack floating ip create ...`
* `openstack server add floating ip ...` 

สิ่งที่ต้องดัก:

* server ชื่อซ้ำ
* volume ชื่อซ้ำ
* flavor/network/security group ไม่ครบ
* root password ไม่มี
* server เข้าสถานะ `ERROR`
* volume ยังไม่พร้อมตอนสร้าง server
* login IP ดึงไม่ได้

สิ่งที่ “ไม่ได้ทำ” ต้องทำยังไง:

* ถ้า VM อยู่แล้ว ไม่ควรสร้างทับ
* ควร fail เลยหรือมี recover policy ชัดเจน
* ตอนนี้ในโค้ด current behavior คือเจอชื่อซ้ำแล้ว fail 

สิ่งที่นาน:

* รอ server ACTIVE
* รอ floating IP association
* ต้อง poll status พร้อม timeout แยกของ server 

---

### Phase 5 — Configure Guest OS

เข้าไปใน VM แล้วปรับแต่ง OS ตาม config ที่เราคุยกันไว้

สิ่งที่ควรเกิดใน phase นี้:

* preflight guest
* baseline official repo test
* LEGACY_MIRROR injection + validation + rollback
* update / upgrade
* reboot / reconnect
* kernel cleanup
* root SSH / root password / per-instance script
* locale / timezone / cloud-init policy
* system policy
* final clean prep

คำสั่งหลักใน phase นี้ส่วนมากจะเป็น

* `ssh`
* `sshpass`
* คำสั่งใน guest เช่น `apt`, `dnf`, `sed`, `cloud-init clean`, `poweroff` ฯลฯ
  และมี openstack บางจุดไว้เช็ก server status ตอน reboot/clean 

---

### Phase 6 — Clean Guest and Poweroff

ก่อน publish final image ควรทำ final clean แล้วปิดเครื่อง

ลำดับงาน:

1. เข้า guest ไป clean
2. cloud-init clean
3. clear package cache / history / temp / logs
4. reset machine-id
5. remove host keys
6. keep per-instance script
7. poweroff
8. รอ OpenStack เห็น server เป็น `SHUTOFF`

คำสั่งที่ใช้อยู่ตอนนี้:

* remote `cloud-init clean --logs`
* `apt clean`
* ลบ `/var/lib/cloud/instance*`
* truncate machine-id
* remove ssh host keys
* `poweroff`
* แล้วใช้ `openstack server show -c status` เช็กว่า `SHUTOFF` 

สิ่งที่ต้องดัก:

* remote clean fail
* SSH session ตัดเพราะ poweroff แต่จริง ๆ clean สำเร็จแล้ว
* server ไม่ยอมเข้า `SHUTOFF`

โค้ดตอนนี้มี logic ดีอยู่ข้อหนึ่ง:

* ถ้า remote SSH หลุดด้วย exit 255 หลังสั่ง poweroff แต่เจอ marker ว่า clean เสร็จแล้ว ก็ถือเป็น success ได้ 

---

### Phase 7 — Delete Server Before Publish

อันนี้ควรอยู่ “ก่อน upload final image” ไม่ใช่หลัง

เหตุผล:

* final image มาจาก volume
* ถ้า server ยัง attach volume อยู่ อาจ upload ไม่ได้หรือ state ไม่พร้อม
* ทางที่ปลอดภัยคือเอา server ลงก่อน แล้วรอ volume กลับมา `available`

ลำดับงาน:

1. เช็กว่ามี final image อยู่แล้วไหม
2. ถ้ายังไม่มี ให้เช็ก source state:

   * server ยังอยู่ไหม
   * volume ยังอยู่ไหม
   * base image ยังอยู่ไหม
3. ถ้า server ยังอยู่และ policy บอกให้ลบ:

   * `openstack server delete`
   * รอ volume กลับมา `available`

คำสั่งที่ใช้อยู่ตอนนี้:

* `openstack server show`
* `openstack server delete`
* `openstack volume show -c status` 

สิ่งที่ต้องดัก:

* server หายไปแล้ว
* volume ไม่กลับมา `available`
* timeout ตอนรอ detach

สิ่งที่ “ไม่ได้ทำ” ต้องทำยังไง:

* ถ้า server หายแล้ว แต่ volume ยังอยู่ → publish ต่อได้
* ถ้า server หายแล้ว และ volume ก็หาย แต่ final image มีแล้ว → ถือว่าจบแล้วได้
* ถ้า server หายแล้ว และ volume ก็หาย แต่ final image ยังไม่มี → fail/skip พร้อมเหตุผล 

---

### Phase 8 — Upload Final Image from Volume

นี่คือขั้นที่คุณเรียกว่า `upload image final`

ลำดับงาน:

1. เช็กว่ามี final image อยู่แล้วไหม
2. ถ้ามีแล้ว:

   * `recover` → ใช้ของเดิม ถ้า active
   * `replace` → ลบแล้วสร้างใหม่
   * ถ้าไม่เข้า policy → skip/fail
3. ถ้ายังไม่มี:

   * ใช้ `cinder upload-to-image` จาก volume
   * หา final image id
   * รอจน image เป็น `active`
   * set metadata/tags/visibility
4. เขียน final manifest

คำสั่งที่ใช้อยู่ตอนนี้:

* `cinder upload-to-image --disk-format ... --container-format ... --force ...`
* `openstack image list --name ...`
* `openstack image show ... -c status`
* `openstack image set --property ... --tag ...`
* `openstack image delete ...` 

สิ่งที่ต้องดัก:

* final image ชื่อซ้ำ
* `cinder upload-to-image` fail
* image id ดึงไม่ได้
* image ไม่เข้า `active`
* image เข้าสถานะ bad เช่น `killed/deleted/deactivated`

สิ่งที่ “ไม่ได้ทำ” ต้องทำยังไง:

* ถ้า final image มีอยู่แล้วและ active:

  * ถ้า policy = `recover` → ถือว่าสำเร็จได้เลย
* ถ้า final image ยังอยู่แต่กำลัง `queued/saving/importing`:

  * รอต่อได้
* ถ้าค่า policy = `replace`:

  * ลบ final image เก่าแล้วสร้างใหม่ 

สิ่งที่นาน:

* `cinder upload-to-image`
* image activation หลัง upload
* ต้องมี timeout และ interval polling แยกเฉพาะ final image เช่น `WAIT_FINAL_TIMEOUT_SECONDS`, `WAIT_FINAL_INTERVAL_SECONDS` 

---

### Phase 9 — Cleanup After Publish

หลัง final image พร้อมแล้ว ค่อยเก็บกวาด resource

ลำดับงาน:

1. ลบ volume ถ้า policy เปิดไว้
2. ลบ base image ถ้า policy เปิดไว้
3. เขียน state/manifest ว่าจบแล้ว

คำสั่งที่ใช้อยู่ตอนนี้:

* `openstack volume delete`
* `openstack image delete` 

สิ่งที่ต้องดัก:

* volume ยังลบไม่ได้เพราะ state ยังไม่พร้อม
* volume delete fail ชั่วคราว
* base image delete fail

โค้ดตอนนี้มี logic ที่ดีอยู่:

* รอให้ volume อยู่ใน state ที่ลบได้ก่อน
* retry volume delete หลายรอบ
* ถ้าลบไม่ได้ก็ log ไว้ ไม่ทำให้ผล publish หายหมดทันที 

---

## ลำดับที่ผมแนะนำแบบสั้นที่สุด

ถ้าสรุปเป็น pipeline ชัด ๆ ที่ควรใช้คือ:

1. **Preflight OpenStack**
2. **Sync / Discover image**
3. **Import base image to Glance**
4. **Create boot volume from base image**
5. **Create VM from volume**
6. **Configure guest**
7. **Final clean + poweroff**
8. **Delete server / wait volume available**
9. **Upload final image from volume**
10. **Delete volume**
11. **Delete base image**
12. **Done**

อันนี้เรียงให้ “resource flow” ถูกต้องที่สุด:

* image base → volume → vm → configure → volume กลับมา → final image

---

## คำสั่งหลักที่ระบบต้องมี

ถ้าแยกเป็นกลุ่มคำสั่ง OpenStack จริง ๆ ตอนนี้คุณต้องใช้ประมาณนี้

### Auth / Validation

* `openstack token issue`
* `openstack project show`
* `openstack image list/show`
* `openstack server list/show`
* `openstack volume list/show`

### Base image

* `openstack image create`
* `openstack image set`
* `openstack image delete`

### Volume

* `openstack volume create`
* `openstack volume show`
* `openstack volume delete`

### Server

* `openstack server create`
* `openstack server show`
* `openstack server delete`
* `openstack server start`
* `openstack server add floating ip`

### Floating IP

* `openstack floating ip create`

### Final image publish

* `cinder upload-to-image`

ทั้งหมดนี้เห็นร่องรอยการใช้งานอยู่ใน phases ปัจจุบันแล้ว     

---

## ดักอะไรบ้าง

สิ่งที่ pipeline นี้ต้องดักให้ดีมี 6 กลุ่ม

### 1) Resource already exists

* base image ชื่อซ้ำ
* server ชื่อซ้ำ
* volume ชื่อซ้ำ
* final image ชื่อซ้ำ

ทางออก:

* policy ชัด: error / skip / replace / recover

### 2) Status transition ไม่มา

* image ไม่ active
* volume ไม่ available
* server ไม่ ACTIVE
* server ไม่ SHUTOFF
* final image ไม่ active

ทางออก:

* poll status
* timeout
* log status ล่าสุด

### 3) Source state ไม่ครบ

* final image ยังไม่มี
* server หายแล้ว
* volume ยังอยู่หรือไม่อยู่
* base image ยังอยู่หรือไม่อยู่

ทางออก:

* recover ถ้า final image มีแล้ว
* continue จาก volume ถ้า server ไม่มีแต่ volume มี
* fail/skip ถ้า source หายหมด

### 4) OpenStack config ไม่ครบ

* network/flavor/volume type/security group ไม่มี
* openrc ไม่ถูก
* project ไม่ตรง

ทางออก:

* preflight validation ก่อน create

### 5) Guest-side issues

* SSH เข้าไม่ได้
* reboot แล้วไม่กลับ
* clean ไม่ครบ
* machine poweroff แล้ว session หลุด

ทางออก:

* remote markers
* reconnect loops
* treat expected disconnect after poweroff เป็น success เมื่อมี marker ครบ

### 6) Cleanup failures

* volume delete ไม่ผ่าน
* image delete ไม่ผ่าน

ทางออก:

* retry
* log
* ไม่พังทั้ง pipeline ถ้า final image สำเร็จแล้วแต่ cleanup บางอย่างยังเหลือ

---

## ถ้าบางอัน “ไม่ได้ทำ” ควรตัดสินยังไง

ผมสรุป decision logic ให้แบบตรง ๆ

### กรณี base image มีแล้ว

* `skip` → ใช้ของเดิม
* `replace` → ลบแล้วสร้างใหม่
* `error` → หยุด

### กรณี server หายแล้วก่อน publish

* ถ้า volume ยังอยู่ → publish ต่อจาก volume ได้
* ถ้า volume หายด้วย แต่ final image มีแล้ว → ถือว่าจบ
* ถ้า volume หายด้วย และ final image ยังไม่มี → fail/skip

### กรณี final image มีอยู่แล้ว

* `recover` → ใช้ของเดิม ถ้า active
* `replace` → ลบแล้วสร้างใหม่
* อื่น ๆ → skip/fail ตาม policy

### กรณี cleanup บางอย่างไม่สำเร็จ

* ถ้า final image สำเร็จแล้ว → ถือว่า pipeline สำเร็จได้ แต่ต้อง log resource leak ไว้
* เมนูภายหลังค่อยมี cleanup/reconcile ช่วยเก็บตก

---

## ถ้าบางอัน “นาน” ควรทำยังไง

สิ่งที่นานจริงใน pipeline นี้คือ:

* image import
* volume clone/create
* server boot
* guest reboot
* cinder upload-to-image
* volume detach after server delete

หลักการที่ควรใช้คือ:

1. **ทุกขั้นที่นานต้องมี polling**
2. **ทุก polling ต้องมี timeout**
3. **ทุก timeout ต้องบอก last known status**
4. **ต้องเขียน log/state ระหว่างรอ**
5. **อย่าใช้ sleep ตายตัวแบบยาวแล้วเงียบ**

ตัวอย่าง timeout ที่โค้ดปัจจุบันมีแล้ว:

* `WAIT_TIMEOUT_SECONDS` สำหรับ image import 
* `WAIT_SERVER_ACTIVE_SECS` และ `WAIT_VOLUME_SECS` สำหรับ create VM/volume 
* `WAIT_FINAL_TIMEOUT_SECONDS` / `WAIT_FINAL_INTERVAL_SECONDS` สำหรับ final image publish 

---

## ถ้าจะทำให้ pipeline นี้ “ดีขึ้นกว่าของเดิม”

ผมแนะนำ 4 จุดสำคัญ

1. แยก state เป็น phase ชัด ๆ

* `import-base`
* `create-volume`
* `create-vm`
* `configure`
* `clean`
* `publish-final`
* `cleanup`

2. มี policy ชัดทุก resource

* on base exists
* on final exists
* on cleanup fail

3. มี reconcile command ภายหลัง

* ดูว่าค้าง volume ไหน
* มี base image ไหนไม่ได้ลบ
* final image ไหน publish แล้วแต่ state ยังไม่ตรง

4. เก็บ runtime manifest เป็น JSON
   เพื่อให้เมนูและ AI อ่านง่ายในอนาคต

---
ได้ ผมจัดให้แบบเต็ม และจะเขียนเป็น “สเปกที่เอาไปทำงานต่อได้” โดยอิงจาก flow ที่มีอยู่จริงใน branch ปัจจุบัน เช่น `import_one.sh`, `create_one.sh`, `configure_one.sh`, `clean_one.sh`, และ `publish_one.sh` ซึ่งตอนนี้ใช้ `openstack image create`, `openstack volume create --image`, `openstack server create --volume`, remote SSH configure, `openstack server delete`, และ `cinder upload-to-image` อยู่แล้ว     

# OpenStack Pipeline ที่ควรเป็น

อันนี้คือลำดับที่ผมแนะนำให้ถือเป็นมาตรฐานกลางของระบบ

1. Preflight / Auth
2. Sync / Discover image
3. Import base image to Glance
4. Create boot volume from base image
5. Create VM from volume
6. Configure guest
7. Final clean + poweroff
8. Delete server / wait volume available
9. Upload final image from volume
10. Delete final source volume
11. Delete base image
12. Final reconcile / state write

นี่คือ resource flow ที่ถูกสุด:

`local upstream image -> glance base image -> cinder boot volume -> nova server -> guest configure -> poweroff -> upload final image from volume -> cleanup`

---

# Command-by-command Checklist

## Phase 0 — Preflight / Auth

เป้าหมายคือเช็กว่าพร้อมใช้ OpenStack จริงก่อนแตะ resource

### Input ที่ต้องมี

* OpenStack env settings
* `openrc`
* naming policy
* project/network/flavor/security group/volume type

### คำสั่งหลัก

```bash
openstack token issue
openstack project show ...
openstack image list --name ...
openstack server list --name ...
openstack volume list --name ...
```

โค้ดปัจจุบันทำแนวนี้ใน preflight อยู่แล้ว และยังมี logic เช็ก project name, naming templates, และ list resource ที่มี prefix ตรงกับระบบด้วย 

### Checklist

```text
[ ] source openrc สำเร็จ
[ ] openstack token issue ผ่าน
[ ] project ปัจจุบันตรงกับที่คาด
[ ] network / flavor / security group / volume type มีค่าพร้อม
[ ] naming template ใช้งานได้จริง
[ ] เช็ก resource ที่มีอยู่แล้วเพื่อกันชนชื่อ
```

### Failure handling

```text
[ ] ถ้า openrc ไม่มี -> fail ทันที
[ ] ถ้า token issue ไม่ผ่าน -> fail ทันที
[ ] ถ้า project mismatch -> fail ทันที
[ ] ถ้า naming template malformed -> fallback default หรือ fail ตาม policy
```

### สถานะที่ควรเขียน

* `preflight-ok`
* `preflight-failed`

---

## Phase 1 — Sync / Discover Base Image

เป้าหมายคือ resolve ว่า image ที่จะใช้จริงคืออะไร โดยยังไม่แตะ OpenStack หนัก

### Input

* `config/os/<os>/sync.env`

### Output

* artifact name
* checksum
* local path
* release page
* artifact URL
* format candidate

### Checklist

```text
[ ] load sync rules
[ ] วน tracked versions
[ ] resolve release/checksum source
[ ] match image candidates
[ ] เลือก amd64/x86_64
[ ] เลือก .img ก่อน ถ้าไม่มีค่อย qcow2
[ ] dry-run หรือ download จริง
[ ] เขียน runtime/state/sync/<os>-<version>.json
[ ] เขียน flag เช่น .dryrun-ok หรือ .ready
```

อันนี้เราคุยกันล็อกแล้วก่อนหน้า

---

## Phase 2 — Import Base Image to Glance

เป้าหมายคือเอาไฟล์ local image ที่ sync มาแล้ว ไปสร้างเป็น base image บน Glance

### คำสั่งที่ใช้จริงตอนนี้

```bash
qemu-img info <local_path>
openstack image list --name <image_name> -f value -c ID
openstack image create <image_name> \
  --file <local_path> \
  --disk-format <raw|qcow2> \
  --container-format bare \
  --private|--public|--community|--shared
openstack image set --tag ...
openstack image show <image_id> -f value -c status
openstack image delete <image_id>
```



### Checklist แบบละเอียด

```text
[ ] อ่าน sync summary/manifest ของ version เป้าหมาย
[ ] เช็กว่า local image file มีอยู่จริง
[ ] ใช้ qemu-img info ตรวจ disk format
[ ] อนุญาตเฉพาะ raw / qcow2
[ ] สร้างชื่อ base image จาก template
[ ] เช็กว่าชื่อนี้มีใน Glance แล้วหรือยัง

[ ] ถ้า image มีอยู่แล้ว:
    - ON_EXISTS=error   -> fail
    - ON_EXISTS=skip    -> ใช้ image เดิม
    - ON_EXISTS=replace -> ลบ image เดิมก่อน

[ ] ถ้าต้องสร้างใหม่:
    - openstack image create
    - set tags/properties
    - wait จน image status = active
    - ถ้า status เข้ากลุ่ม bad -> fail
    - ถ้า timeout -> fail

[ ] เขียน manifest ของ base image
[ ] เขียน state current.base-image-<version>
```

### ต้องดักอะไร

```text
[ ] local_path หาย
[ ] qemu-img detect format ไม่ได้
[ ] format ไม่รองรับ
[ ] image name ซ้ำ
[ ] image create ไม่ได้
[ ] image status ไม่ active
[ ] image status = killed/deleted/deactivated
[ ] timeout รอ image active
```

### ถ้าบางอัน “ไม่ต้องทำ”

```text
[ ] ถ้า image มีอยู่แล้วและ ON_EXISTS=skip -> ไม่ต้อง import ใหม่
```

### ถ้าบางอัน “นาน”

```text
[ ] poll image status ทุก interval
[ ] มี timeout แยก
[ ] log status ล่าสุดตลอด
```

---

## Phase 3 — Create Boot Volume from Base Image

เป้าหมายคือสร้าง boot volume จาก Glance base image

### คำสั่งที่ใช้จริงตอนนี้

```bash
openstack volume create \
  --image <BASE_IMAGE_ID> \
  --size <VOLUME_SIZE_GB> \
  --type <VOLUME_TYPE> \
  -f value -c id <VOLUME_NAME>

openstack volume show <VOLUME_ID> -f value -c status
```



### Checklist

```text
[ ] อ่าน manifest ของ base image
[ ] เช็ก BASE_IMAGE_ID / BASE_IMAGE_NAME ครบ
[ ] เช็ก BASE_IMAGE_ID ยังมีอยู่จริงใน Glance
[ ] สร้างชื่อ volume
[ ] เช็กชื่อ volume ไม่ชนของเดิม
[ ] create volume from image
[ ] wait จน volume status = available
[ ] ถ้า status เข้ากลุ่ม error -> fail
[ ] ถ้า timeout -> fail
```

### ต้องดักอะไร

```text
[ ] BASE_IMAGE_ID ไม่มี
[ ] image ถูกลบไปแล้ว
[ ] volume type ไม่ถูก
[ ] size ไม่ถูก
[ ] volume create fail
[ ] volume status = error*
[ ] timeout waiting available
```

### ถ้าบางอัน “นาน”

```text
[ ] volume clone จาก image อาจใช้เวลานานมาก
[ ] ต้อง poll status พร้อม timeout
```

---

## Phase 4 — Create VM from Volume

เป้าหมายคือสร้าง VM จาก boot volume แล้วให้เข้า guest ได้

### คำสั่งที่ใช้จริงตอนนี้

```bash
openstack server create \
  --flavor <FLAVOR_ID> \
  --network <NETWORK_ID> \
  --security-group <SECURITY_GROUP> \
  --volume <VOLUME_ID> \
  --user-data <USER_DATA_FILE> \
  [--key-name <KEY_NAME>] \
  -f value -c id <VM_NAME>

openstack server show <SERVER_ID> -f value -c status
openstack server show <SERVER_ID> -f value -c addresses

openstack floating ip create <FLOATING_NETWORK> -f value -c floating_ip_address
openstack server add floating ip <SERVER_ID> <FLOATING_IP>
```



### Checklist

```text
[ ] volume ต้อง available แล้ว
[ ] compose VM_NAME และ VOLUME_NAME ตาม template
[ ] เช็กชื่อ VM ไม่ชน
[ ] เช็กชื่อ volume ไม่ชน
[ ] สร้าง user-data/cloud-init สำหรับ root access
[ ] create server from volume
[ ] wait จน server status = ACTIVE
[ ] ดึง addresses
[ ] เลือก FIXED_IP หรือ FLOATING_IP เป็น LOGIN_IP
[ ] ถ้าต้องใช้ floating IP:
    - existing IP -> attach
    - floating network -> allocate แล้ว attach
[ ] เขียน output env/state สำหรับ configure phase
```

### ต้องดักอะไร

```text
[ ] FLAVOR_ID / NETWORK_ID / SECURITY_GROUP / VOLUME_TYPE / VOLUME_SIZE_GB ไม่ครบ
[ ] ROOT_PASSWORD ไม่มี
[ ] server name ซ้ำ
[ ] volume name ซ้ำ
[ ] server create fail
[ ] server status = ERROR
[ ] ไม่มี LOGIN_IP
[ ] floating IP create/attach fail
```

### ถ้าบางอัน “ไม่ต้องทำ”

```text
[ ] ถ้าไม่มี floating IP policy -> ใช้ fixed IP ต่อได้
[ ] ถ้ามี existing floating IP อยู่แล้ว -> ไม่ต้อง allocate ใหม่
```

### ถ้าบางอัน “นาน”

```text
[ ] poll server ACTIVE
[ ] poll/validate IP หลัง ACTIVE
[ ] timeout แยกของ server
```

---

## Phase 5 — Configure Guest

เป้าหมายคือเข้า guest แล้วปรับแต่ง OS ให้พร้อม

โค้ดปัจจุบันของ `configure_one.sh` ทำเป็น 2 ช่วง คือ `pre` และ `post` ผ่าน remote script โดยมีการเลือก repo mode, รัน `apt-get update`, `apt-get upgrade`, ตั้ง SSH root, locale, timezone, cloud-init, disable auto-update/MOTD/UFW และ cleanup kernels 

### คำสั่งที่ใช้จริงในปัจจุบัน

ฝั่ง local:

```bash
ssh
scp
sshpass   # ถ้าใช้ password
```

ฝั่ง guest:

```bash
cloud-init status --wait
apt-get update
apt-get upgrade -y
chpasswd
sshd -t
systemctl restart ssh || systemctl restart sshd
locale-gen
update-locale
timedatectl set-timezone
systemctl disable --now unattended-upgrades
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer
systemctl disable --now ufw
ufw disable
dpkg-query -W 'linux-image-[0-9]*'
apt-get purge -y ...
apt-get autoremove -y
```



### Checklist

```text
[ ] รอ SSH พร้อม
[ ] upload remote configure script
[ ] run pre phase
    - wait cloud-init
    - detect OS/version
    - baseline repo update
    - choose repo mode
    - write apt sources
    - fallback update if needed
    - upgrade
    - configure SSH root policy
    - configure locale/timezone
    - configure cloud-init policy
    - disable auto-updates / MOTD / firewall

[ ] ถ้าต้อง reboot:
    - reboot
    - wait SSH กลับมา
    - upload script ใหม่
    - run post phase

[ ] post phase:
    - wait cloud-init
    - detect OS/version อีกครั้ง
    - kernel cleanup
    - validate state
    - cleanup temp backup artifacts
```

### ต้องดักอะไร

```text
[ ] SSH เข้าไม่ได้
[ ] root password / SSH key ไม่พร้อม
[ ] apt update fail
[ ] repo mode เลือกไม่ถูก
[ ] fallback official/old-releases fail
[ ] upgrade fail
[ ] sshd -t ไม่ผ่าน
[ ] restart ssh fail
[ ] reboot แล้ว VM ไม่กลับ
[ ] locale/timezone ไม่ถูก
[ ] kernel cleanup fail
```

### ถ้าบางอัน “ไม่ต้องทำ”

```text
[ ] ถ้า DO_UPGRADE=no -> ข้าม upgrade
[ ] ถ้า REBOOT_AFTER_UPGRADE=no -> ข้าม reboot
```

### ถ้าบางอัน “นาน”

```text
[ ] cloud-init status --wait อาจนาน -> timeout
[ ] apt upgrade อาจนานมาก -> log command output ต่อเนื่อง
[ ] reboot/reconnect ต้องมี loop รอ SSH
```

---

## Phase 6 — Final Clean + Poweroff

เป้าหมายคือ clean image ก่อน publish final

โค้ด `clean_one.sh` ตอนนี้ทำ remote clean, cloud-init clean, ลบ machine-id/host keys/history/tmp, `apt clean`, แล้วสั่ง poweroff และรอจน server เป็น `SHUTOFF` 

### คำสั่งที่ใช้จริง

ฝั่ง guest:

```bash
cloud-init clean --logs
rm -rf /var/lib/cloud/instances/* /var/lib/cloud/instance /var/lib/cloud/sem/*
rm -f /etc/netplan/50-cloud-init.yaml
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
rm -f /root/.ssh/authorized_keys
rm -f /var/lib/cloud/scripts/per-instance/10-root-authorized-keys.sh   # ของโค้ดปัจจุบันลบ
apt clean
rm -rf /var/lib/apt/lists/*
rm -f /root/.bash_history
rm -f /home/*/.bash_history
rm -rf /tmp/* /var/tmp/*
poweroff
```

ฝั่ง OpenStack:

```bash
openstack server show <SERVER_ID> -f value -c status
```



### Checklist

```text
[ ] เข้า guest ได้
[ ] run final clean
[ ] clear cloud-init state/logs
[ ] clear apt cache / lists
[ ] reset machine-id
[ ] remove ssh host keys
[ ] clear shell history
[ ] clear temp files
[ ] poweroff
[ ] wait server status = SHUTOFF
```

### ต้องดักอะไร

```text
[ ] remote clean fail
[ ] SSH session หลุดเพราะ poweroff
[ ] server ไม่เข้า SHUTOFF
```

### จุดสำคัญ

ในโค้ดตอนนี้มี logic ที่ถือว่า exit 255 หลัง poweroff เป็น success ได้ ถ้า log มี completion markers ครบ อันนี้ควรเก็บไว้ 

---

## Phase 7 — Delete Server / Wait Volume Available

เป้าหมายคือทำให้ volume หลุดจาก server ก่อน publish

โค้ด `publish_one.sh` ตอนนี้รองรับทั้งกรณี server ยังอยู่, server หายแล้วแต่ volume ยังอยู่, และ final image มีแล้วแบบ recover mode 

### คำสั่งที่ใช้จริง

```bash
openstack server show <SERVER_ID>
openstack server delete <SERVER_ID>
openstack volume show <VOLUME_ID> -f value -c status
```

### Checklist

```text
[ ] เช็กว่า final image มีอยู่แล้วหรือยัง
[ ] เช็ก source state:
    - server present?
    - volume present?
    - base image present?
[ ] ถ้า server present และ policy ให้ลบ:
    - delete server
    - wait volume status = available
[ ] ถ้า server absent แต่ volume present:
    - continue publish from volume
[ ] ถ้า server absent และ volume absent:
    - ถ้า final image มีแล้ว -> ถือว่าสำเร็จ
    - ถ้ายังไม่มี -> fail/skip
```

### ต้องดักอะไร

```text
[ ] server delete fail
[ ] volume ไม่กลับมา available
[ ] timeout detach
```

---

## Phase 8 — Upload Final Image from Volume

เป้าหมายคือใช้ volume ที่ configure เสร็จแล้ว อัปโหลดขึ้นเป็น final image

### คำสั่งที่ใช้จริง

```bash
cinder upload-to-image \
  --disk-format <qcow2|raw> \
  --container-format bare \
  --force <True|...> \
  <VOLUME_ID> <FINAL_IMAGE_NAME>

openstack image list --name <FINAL_IMAGE_NAME> -f value -c ID
openstack image show <FINAL_IMAGE_ID> -f value -c status
openstack image set --property ...
openstack image set --tag ...
openstack image delete <FINAL_IMAGE_ID>
```



### Checklist

```text
[ ] compose FINAL_IMAGE_NAME
[ ] เช็กว่ามี final image ชื่อนี้อยู่แล้วไหม

[ ] ถ้ามีอยู่แล้ว:
    - ON_FINAL_EXISTS=recover -> ถ้า active ใช้ของเดิม
    - ON_FINAL_EXISTS=replace -> ลบของเดิมแล้วสร้างใหม่
    - otherwise -> skip/fail ตาม policy

[ ] ถ้ายังไม่มี:
    - cinder upload-to-image
    - parse image_id จาก output
    - ถ้าดึง image_id ไม่ได้ -> หาโดย image name
    - wait final image status = active
    - set properties
    - set tags
    - set visibility
    - เขียน manifest final-image-<version>.env
```

### ต้องดักอะไร

```text
[ ] final image name ซ้ำ
[ ] upload-to-image fail
[ ] image_id parse ไม่ได้
[ ] image ไม่ active
[ ] image status = killed/deleted/deactivated
[ ] timeout waiting final image active
```

### ถ้าบางอัน “ไม่ต้องทำ”

```text
[ ] ถ้ามี final image อยู่แล้วและ active และ policy=recover -> ไม่ต้อง upload ใหม่
```

### ถ้าบางอัน “นาน”

```text
[ ] cinder upload-to-image อาจนานมาก
[ ] image activation หลัง upload อาจนาน
[ ] ต้อง poll status พร้อม timeout แยก
```

---

## Phase 9 — Cleanup Volume and Base Image

เป้าหมายคือเก็บกวาด source resources หลัง final image สำเร็จ

### คำสั่งที่ใช้จริง

```bash
openstack volume delete <VOLUME_ID>
openstack image delete <BASE_IMAGE_ID>
openstack volume show <VOLUME_ID> -f value -c status
```



### Checklist

```text
[ ] ถ้า policy เปิด -> delete volume
[ ] wait/validate volume เข้าสถานะที่ลบได้
[ ] retry delete volume หลายรอบถ้าจำเป็น
[ ] ถ้า policy เปิด -> delete base image
[ ] log cleanup result
```

### ต้องดักอะไร

```text
[ ] volume ยังไม่ detachable/deletable
[ ] volume delete fail ชั่วคราว
[ ] base image delete fail
```

### หลักสำคัญ

ถ้า final image สำเร็จแล้ว แต่ cleanup บางอย่าง fail:

* ไม่ควรถือว่าทั้ง pipeline ล้มเหลว
* ควร mark success with cleanup warnings
* แล้วให้เมนู cleanup/reconcile ช่วยเก็บตกภายหลัง

---

# Runtime JSON Schema

ต่อไปคือ schema JSON ที่ผมแนะนำสำหรับ runtime state ของ phase หลัก

## กติกากลาง

ทุก phase ควรมี fields กลางร่วมกันแบบนี้

```json
{
  "schema_version": "1.0",
  "phase": "import|create|configure|publish",
  "os_family": "ubuntu",
  "os_version": "24.04",
  "run_id": "20260322120000",
  "started_at": "2026-03-22T12:00:00Z",
  "finished_at": "2026-03-22T12:10:00Z",
  "final_status": "ready|failed|skipped|recovered|partial",
  "failure_phase": "",
  "failure_reason": "",
  "log_path": "runtime/logs/...log",
  "state_flags": [
    "..."
  ]
}
```

---

## 1) Import Phase JSON

ไฟล์:

```text
runtime/state/import/<os>-<version>.json
```

ตัวอย่าง schema:

```json
{
  "schema_version": "1.0",
  "phase": "import",
  "os_family": "ubuntu",
  "os_version": "24.04",
  "run_id": "20260322120000",
  "source": {
    "summary_file": "runtime/state/sync/ubuntu-24.04.json",
    "artifact_name": "ubuntu-24.04-server-cloudimg-amd64.img",
    "local_path": "workspace/images/ubuntu/24.04/ubuntu-24.04-server-cloudimg-amd64.img",
    "release_page": "https://...",
    "artifact_url": "https://...",
    "expected_sha256": "abc123...",
    "disk_format_detected": "raw"
  },
  "glance": {
    "image_name": "ubuntu-24.04-base-official",
    "image_id": "uuid",
    "visibility": "private",
    "tags": [
      "source:official",
      "stage:base",
      "os:ubuntu"
    ],
    "status": "active",
    "on_exists_policy": "skip"
  },
  "wait": {
    "enabled": true,
    "timeout_seconds": 1800,
    "interval_seconds": 10,
    "last_status": "active"
  },
  "result": {
    "manifest_file": "runtime/state/import/ubuntu-24.04-base.json"
  },
  "started_at": "2026-03-22T12:00:00Z",
  "finished_at": "2026-03-22T12:03:00Z",
  "final_status": "ready",
  "failure_phase": "",
  "failure_reason": "",
  "log_path": "runtime/logs/import/ubuntu-24.04.log",
  "state_flags": [
    "base-imported",
    "base-active"
  ]
}
```

---

## 2) Create Phase JSON

ไฟล์:

```text
runtime/state/create/<os>-<version>.json
```

ตัวอย่าง schema:

```json
{
  "schema_version": "1.0",
  "phase": "create",
  "os_family": "ubuntu",
  "os_version": "24.04",
  "run_id": "20260322121000",
  "input": {
    "base_image_name": "ubuntu-24.04-base-official",
    "base_image_id": "uuid",
    "network_id": "uuid",
    "flavor_id": "uuid",
    "security_group": "allow-any",
    "volume_type": "cinder",
    "volume_size_gb": 10
  },
  "volume": {
    "name": "ubuntu-24-04-ci-20260322121000-boot",
    "id": "uuid",
    "status": "available",
    "wait_timeout_seconds": 600
  },
  "server": {
    "name": "ubuntu-24-04-ci-20260322121000",
    "id": "uuid",
    "status": "ACTIVE",
    "wait_timeout_seconds": 600
  },
  "network": {
    "addresses_raw": "private=10.0.0.15, floating=1.2.3.4",
    "fixed_ip": "10.0.0.15",
    "floating_ip": "1.2.3.4",
    "login_ip": "1.2.3.4"
  },
  "access": {
    "ssh_user": "root",
    "ssh_port": 22,
    "password_auth_enabled": true
  },
  "output_files": {
    "configure_env": "runtime/state/create/ubuntu-24.04.configure.env"
  },
  "started_at": "2026-03-22T12:10:00Z",
  "finished_at": "2026-03-22T12:18:00Z",
  "final_status": "ready",
  "failure_phase": "",
  "failure_reason": "",
  "log_path": "runtime/logs/create/ubuntu-24.04.log",
  "state_flags": [
    "volume-ready",
    "server-active",
    "guest-login-ready"
  ]
}
```

---

## 3) Configure Phase JSON

ไฟล์:

```text
runtime/state/configure/<os>-<version>.json
```

ตัวอย่าง schema:

```json
{
  "schema_version": "1.0",
  "phase": "configure",
  "os_family": "ubuntu",
  "os_version": "24.04",
  "run_id": "20260322122000",
  "input": {
    "server_id": "uuid",
    "volume_id": "uuid",
    "vm_name": "ubuntu-24-04-ci-20260322121000",
    "vm_host": "1.2.3.4",
    "ssh_user": "root",
    "ssh_port": 22,
    "config_default_file": "config/guest/ubuntu/default.env",
    "config_version_file": "config/guest/ubuntu/24.04.env"
  },
  "effective_config": {
    "LEGACY_MIRROR_ENABLED": "yes",
    "LEGACY_MIRROR_FAILOVER_TO_OFFICIAL": "yes",
    "TIMEZONE": "Asia/Bangkok",
    "KERNEL_KEEP": "2",
    "DISABLE_AUTO_UPDATES": "yes"
  },
  "repo": {
    "repo_mode_selected": "ols",
    "repo_mode_effective": "ols",
    "fallback_used": false,
    "apt_source_mode": "sources.list"
  },
  "phase_status": {
    "resolve_config": "ok",
    "guest_preflight": "ok",
    "baseline_official": "ok",
    "repo_backup": "ok",
    "legacy_mirror_injection": "ok",
    "legacy_mirror_validation": "ok",
    "update_upgrade": "ok",
    "reboot_reconnect": "ok",
    "kernel_cleanup": "ok",
    "access_policy": "ok",
    "system_policy": "ok",
    "repo_revalidation": "ok",
    "final_clean_prep": "ok"
  },
  "artifacts": {
    "remote_log": "/var/log/phase2-config-20260322122000.log",
    "remote_log_copy": "runtime/logs/configure/remote_phase2_1.2.3.4_20260322122000.log",
    "summary_file": "runtime/logs/configure/ubuntu-24.04.summary.txt"
  },
  "started_at": "2026-03-22T12:20:00Z",
  "finished_at": "2026-03-22T12:35:00Z",
  "final_status": "ready",
  "failure_phase": "",
  "failure_reason": "",
  "log_path": "runtime/logs/configure/ubuntu-24.04.log",
  "state_flags": [
    "configure-pre-ok",
    "reboot-ok",
    "configure-post-ok"
  ]
}
```

---

## 4) Publish Phase JSON

ไฟล์:

```text
runtime/state/publish/<os>-<version>.json
```

ตัวอย่าง schema:

```json
{
  "schema_version": "1.0",
  "phase": "publish",
  "os_family": "ubuntu",
  "os_version": "24.04",
  "run_id": "20260322124000",
  "input": {
    "server_id": "uuid",
    "volume_id": "uuid",
    "base_image_id": "uuid",
    "vm_name": "ubuntu-24-04-ci-20260322121000",
    "final_image_name": "ubuntu-24.04-complete-20260322"
  },
  "source_state": {
    "server_present_before_publish": true,
    "volume_present_before_publish": true,
    "base_image_present_before_publish": true
  },
  "server_cleanup": {
    "delete_server_before_publish": true,
    "server_deleted": true,
    "volume_available_after_delete": true
  },
  "publish": {
    "tool": "cinder upload-to-image",
    "disk_format": "qcow2",
    "container_format": "bare",
    "final_image_id": "uuid",
    "final_image_status": "active",
    "wait_timeout_seconds": 3600,
    "wait_interval_seconds": 10
  },
  "metadata": {
    "visibility": "private",
    "tags": [
      "stage:complete",
      "os:ubuntu"
    ],
    "properties": {
      "os_distro": "ubuntu",
      "os_version": "24.04",
      "pipeline_stage": "complete",
      "source_server_id": "uuid",
      "source_volume_id": "uuid",
      "source_base_image_id": "uuid"
    }
  },
  "on_final_exists_policy": "recover",
  "recover": {
    "reused_existing_final_image": false,
    "existing_final_image_id": ""
  },
  "cleanup": {
    "delete_volume_after_publish": true,
    "volume_deleted": true,
    "delete_base_image_after_publish": true,
    "base_image_deleted": true,
    "cleanup_warnings": []
  },
  "artifacts": {
    "manifest_file": "runtime/state/publish/ubuntu-24.04-final.json"
  },
  "started_at": "2026-03-22T12:40:00Z",
  "finished_at": "2026-03-22T13:05:00Z",
  "final_status": "ready",
  "failure_phase": "",
  "failure_reason": "",
  "log_path": "runtime/logs/publish/ubuntu-24.04.log",
  "state_flags": [
    "server-deleted",
    "final-image-active",
    "volume-cleaned",
    "base-image-cleaned",
    "published"
  ]
}
```

---

# Failure Model ที่ควรใช้กับทุก Phase

ทุก JSON ควรเขียนค่าเหล่านี้เสมอเวลา fail

```json
{
  "final_status": "failed",
  "failure_phase": "create-volume",
  "failure_reason": "timeout waiting volume available",
  "last_known_status": "creating"
}
```

หรือเวลา recover

```json
{
  "final_status": "recovered",
  "failure_phase": "",
  "failure_reason": "",
  "recover_mode": "existing-final-image-active"
}
```

หรือเวลา partial success

```json
{
  "final_status": "partial",
  "failure_phase": "cleanup",
  "failure_reason": "final image published but volume cleanup failed"
}
```

---

# สถานะ flag ที่ผมแนะนำ

## Import

* `.base-imported`
* `.base-active`
* `.failed`

## Create

* `.volume-ready`
* `.server-active`
* `.guest-login-ready`
* `.failed`

## Configure

* `.configure-pre-ok`
* `.reboot-ok`
* `.configure-post-ok`
* `.failed`

## Publish

* `.server-deleted`
* `.final-image-active`
* `.published`
* `.cleanup-warning`
* `.failed`

---

# สรุปสั้นที่สุด

ตอนนี้ pipeline OpenStack ที่ควรใช้คือ:

1. preflight auth
2. sync/discover
3. import base image
4. create volume from image
5. create vm from volume
6. configure guest
7. clean + poweroff
8. delete server / wait volume available
9. upload final image from volume
10. delete volume
11. delete base image
12. write final runtime JSON + flags

และ runtime JSON ที่ดีที่สุดคือ:

* แยกตาม phase
* มี common fields กลาง
* มี phase-specific sections
* เก็บทั้ง status, failure point, wait info, cleanup result, log path

ได้ อันนี้คือแบบจัดเต็มของหัวข้อ
**ออกแบบ `openstack_api.sh` และ `common_utils.sh`**
เพื่อไม่ให้ logic พวก `polling / timeout / retry / error handling / openstack command` กระจายเต็มทุก phase

ผมจะสรุปเป็น 6 ส่วน:

1. ตอนนี้ปัญหาคืออะไร
2. หลักการแยกหน้าที่ 2 ไฟล์นี้
3. `openstack_api.sh` ควรมีฟังก์ชันอะไรบ้าง
4. `common_utils.sh` ควรมีฟังก์ชันอะไรบ้าง
5. ตัวอย่างว่าแต่ละ phase จะเรียกยังไง
6. สิ่งที่ไม่ควรใส่ใน 2 ไฟล์นี้

---

# 1) ตอนนี้ปัญหาคืออะไร

จาก phases ปัจจุบัน จะเห็นว่า logic เดิมมันกระจายซ้ำในหลายไฟล์ เช่น

* เช็กคำสั่งที่จำเป็น (`need_cmd`)
* log / die / trap
* loop รอ status
* timeout
* เช็กว่า resource มีอยู่หรือไม่
* create / delete / wait ของ image / volume / server
* SSH helper และ reconnect logic
* การ parse output จาก OpenStack

ตัวอย่าง:

* `phases/preflight.sh` มี `need_cmd`, `log`, `warn`, `die`, และเช็ก project/resource ต่าง ๆ 
* `phases/import_one.sh` มี `need_cmd`, `log`, `die`, loop รอ image active, และ policy `ON_EXISTS` ของ image import 
* `phases/create_one.sh` มี loop รอ volume available, loop รอ server ACTIVE, logic allocate floating IP, และ logic เช็กชื่อซ้ำ 
* `phases/configure_one.sh` มี SSH helper, SCP helper, wait SSH, fetch remote log, error trap, reboot/reconnect logic 
* `phases/clean_one.sh` มี wait server SHUTOFF, remote run, SSH/retry style logic และ state writing 
* `phases/publish_one.sh` มี `wait_for_volume_status`, `wait_for_image_status`, `delete_volume_with_retry`, `image_exists`, `server_exists`, `volume_exists`, และ publish/recover logic 

สรุปคือ ตอนนี้ phase แต่ละตัว “ทำงานได้” แต่

* โค้ดซ้ำ
* naming ไม่สม่ำเสมอ
* timeout/retry policy กระจัดกระจาย
* แก้ทีหนึ่งต้องไล่แก้หลายไฟล์
* behavior ไม่คงที่

เพราะงั้น 2 ไฟล์นี้ควรเป็นแกนกลางของระบบ

---

# 2) หลักการแยกหน้าที่

ผมแนะนำให้แยกแบบนี้

## `lib/openstack_api.sh`

เอาไว้รวมทุกอย่างที่ “ผูกกับ OpenStack โดยตรง”

เช่น:

* auth check
* list/show/exists
* create image/volume/server
* wait status
* delete resource
* floating IP
* upload final image
* recover/reconcile helpers ที่แตะ OpenStack resource

พูดง่าย ๆ:

> ถ้ามันต้องเรียก `openstack ...` หรือ `cinder ...` เป็นหลัก
> มันควรอยู่ `openstack_api.sh`

---

## `lib/common_utils.sh`

เอาไว้รวมทุกอย่างที่ “ใช้ได้ทุก phase” และไม่ผูกเฉพาะ OpenStack

เช่น:

* log / warn / error / die
* require command
* retry
* timeout wrappers
* generic polling
* file/dir helper
* string/template helper
* state/flag write helper
* JSON write helper แบบง่าย
* SSH/SCP common wrappers ถ้าจะยังไม่แยกไฟล์เพิ่ม

พูดง่าย ๆ:

> ถ้า phase ไหนก็ใช้ได้
> และไม่จำเป็นต้องรู้เรื่อง OpenStack
> มันควรอยู่ `common_utils.sh`

---

# 3) `openstack_api.sh` ควรมีอะไรบ้าง

ผมแยกเป็นหมวดให้เลย

---

## A. Auth / Preflight functions

อันนี้ใช้ตั้งแต่ phase แรก

### 1) `os_require_auth`

หน้าที่:

* เช็กว่า auth ใช้งานได้จริง

ภายในควรใช้:

```bash
openstack token issue
```

ใช้เมื่อ:

* ก่อนเข้า create/import/publish
* ก่อนเมนู settings ที่ต้องอ่าน resource จาก cloud

ผลลัพธ์:

* ผ่าน = return 0
* ไม่ผ่าน = return non-zero พร้อม log ชัด

---

### 2) `os_get_current_project_id`

หน้าที่:

* ดึง project id จาก token ปัจจุบัน

ภายในใช้:

```bash
openstack token issue -f value -c project_id
```

---

### 3) `os_get_project_name`

หน้าที่:

* รับ project id หรือ name แล้วคืนชื่อ project

ภายในใช้:

```bash
openstack project show -f value -c name ...
```

---

### 4) `os_validate_expected_project`

หน้าที่:

* เช็กว่า project ปัจจุบันตรงกับที่คาด

ใช้ใน:

* preflight

โค้ดปัจจุบันมี logic คล้าย ๆ นี้อยู่แล้วใน `preflight.sh` 

---

## B. Generic resource existence / show

อันนี้ควรมี เพราะตอนนี้กระจายซ้ำมาก

### 5) `os_image_exists <image_id_or_name>`

### 6) `os_volume_exists <volume_id_or_name>`

### 7) `os_server_exists <server_id_or_name>`

หน้าที่:

* return 0 ถ้ามี
* return 1 ถ้าไม่มี

ภายในใช้:

```bash
openstack image show ...
openstack volume show ...
openstack server show ...
```

โค้ดปัจจุบันมีแนวเดียวกันใน `publish_one.sh` 

---

### 8) `os_get_image_status <image_id>`

### 9) `os_get_volume_status <volume_id>`

### 10) `os_get_server_status <server_id>`

หน้าที่:

* คืน status ปัจจุบัน

ภายในใช้:

```bash
openstack image show ... -f value -c status
openstack volume show ... -f value -c status
openstack server show ... -f value -c status
```

---

### 11) `os_find_image_id_by_name <name>`

หน้าที่:

* หา image id จาก name

ภายในใช้:

```bash
openstack image list --name "$name" -f value -c ID | head -n1
```

โค้ดปัจจุบันมีใช้อยู่ใน `import_one.sh` และ `publish_one.sh`  

---

## C. Wait / Poll functions

อันนี้คือหัวใจของ `openstack_api.sh`

### 12) `os_wait_image_status <image_id> <desired> <timeout> <interval>`

หน้าที่:

* รอ image จนเข้า desired status
* ถ้าเข้า bad status เช่น `killed/deleted/deactivated` ให้ fail
* ถ้า timeout ให้ fail พร้อม last status

โค้ดปัจจุบันมี logic นี้ใน `import_one.sh` และ `publish_one.sh`  

---

### 13) `os_wait_volume_status <volume_id> <desired> <timeout> <interval>`

หน้าที่:

* รอ volume จน `available` หรือ status อื่นตามต้องการ
* ถ้าเข้า `error*` ให้ fail

โค้ดปัจจุบันมีใน `create_one.sh` และ `publish_one.sh`  

---

### 14) `os_wait_server_status <server_id> <desired> <timeout> <interval>`

หน้าที่:

* รอ server จน ACTIVE หรือ SHUTOFF หรือสถานะที่ต้องการ
* ถ้า server เข้า ERROR ให้ fail

โค้ดปัจจุบันมีใน `create_one.sh` และ `clean_one.sh`  

---

### 15) `os_wait_volume_deletable <volume_id> <timeout> <interval>`

หน้าที่:

* รอให้ volume เข้า state ที่ลบได้
* ใช้ใน cleanup หลัง publish

โค้ดปัจจุบันมี logic นี้ใน `publish_one.sh` 

---

## D. Image functions

### 16) `os_create_base_image`

หน้าที่:

* wrap `openstack image create`
* รับชื่อไฟล์ local path, disk format, visibility, properties, tags
* คืน image id

ควรรองรับ:

* visibility
* os_distro / os_version
* source metadata
* tags

โค้ดปัจจุบันของ `import_one.sh` ทำทั้งหมดนี้อยู่แล้ว แต่ควรย้ายมาเป็นฟังก์ชันเดียว 

---

### 17) `os_delete_image <image_id>`

หน้าที่:

* ลบ image

---

### 18) `os_set_image_tags <image_id> <csv_tags>`

หน้าที่:

* รับ csv แล้ว set tag ทีละตัว

---

### 19) `os_set_image_properties <image_id> ...`

หน้าที่:

* ใส่ property หลายตัวให้อ่านง่าย ไม่ต้องเรียก `openstack image set` กระจาย

---

## E. Volume functions

### 20) `os_create_volume_from_image`

หน้าที่:

* สร้าง volume จาก image id
* return volume id

ภายในใช้:

```bash
openstack volume create --image ...
```

โค้ดปัจจุบันอยู่ใน `create_one.sh` 

---

### 21) `os_delete_volume <volume_id>`

หน้าที่:

* ลบ volume ครั้งเดียว

---

### 22) `os_delete_volume_with_retry <volume_id> <attempts>`

หน้าที่:

* รอ deletable state
* ลบซ้ำหลายครั้ง
* log attempt

โค้ดปัจจุบันมีฟังก์ชันนี้อยู่แล้วใน `publish_one.sh` และควรย้ายมารวมศูนย์ 

---

## F. Server functions

### 23) `os_create_server_from_volume`

หน้าที่:

* สร้าง server จาก volume
* รับ flavor/network/security group/user-data/key-name
* return server id

โค้ดปัจจุบันอยู่ใน `create_one.sh` 

---

### 24) `os_delete_server <server_id>`

หน้าที่:

* ลบ server

---

### 25) `os_start_server <server_id>`

### 26) `os_stop_server <server_id>`

หน้าที่:

* ใช้ใน flow clean/recover บางกรณี

---

## G. Floating IP functions

### 27) `os_allocate_floating_ip <network>`

หน้าที่:

* allocate floating IP ใหม่
* return IP address

### 28) `os_attach_floating_ip <server_id> <floating_ip>`

หน้าที่:

* attach IP ให้ server

โค้ดปัจจุบันใช้แนวนี้ใน `create_one.sh` 

---

## H. Publish / Final image functions

### 29) `os_upload_volume_to_image`

หน้าที่:

* wrap `cinder upload-to-image`
* รับ volume id, final image name, disk/container format
* return final image id ถ้า parse ได้

โค้ดปัจจุบันอยู่ใน `publish_one.sh` 

---

### 30) `os_find_or_wait_final_image_id`

หน้าที่:

* ถ้า `upload-to-image` parse image id ไม่ได้
* หา image id จากชื่อใน loop

โค้ดปัจจุบันมี logic นี้ใน `publish_one.sh` 

---

### 31) `os_apply_final_image_metadata`

หน้าที่:

* set visibility
* set tags
* set properties เช่น

  * os_distro
  * os_version
  * pipeline_stage
  * source_server_id
  * source_volume_id
  * source_base_image_id

โค้ดปัจจุบันมีใน `publish_one.sh` และควรรวมเป็น helper เดียว 

---

## I. Discovery functions for Settings menu

เพราะคุณอยากให้เมนู Settings อ่าน project/network/flavor จาก OpenStack ได้

### 32) `os_list_projects`

### 33) `os_list_networks`

### 34) `os_list_flavors`

### 35) `os_list_volume_types`

### 36) `os_list_security_groups`

### 37) `os_list_floating_networks`

หน้าที่:

* คืนข้อมูลแบบ machine-friendly ให้เมนูใช้ต่อ

อันนี้ยังไม่เห็นใน phases ปัจจุบัน แต่ควรอยู่ใน `openstack_api.sh` แน่นอน

---

# 4) `common_utils.sh` ควรมีอะไรบ้าง

อันนี้คือของกลางจริง ๆ

---

## A. Logging / Error functions

### 1) `log_info`

### 2) `log_warn`

### 3) `log_error`

### 4) `die`

หน้าที่:

* log มาตรฐานทุก phase
* format เวลาเหมือนกัน
* ลดการประกาศ `log(){...}` ซ้ำทุกไฟล์

ตอนนี้ `preflight.sh`, `import_one.sh`, `create_one.sh`, `clean_one.sh`, `publish_one.sh` ต่างก็ประกาศ log/die เองหมด     

---

### 5) `init_log_file <path>`

หน้าที่:

* เตรียม log file ให้ phase นั้น
* export ตัวแปรกลางเช่น `CURRENT_LOG_FILE`

---

### 6) `trap_with_context`

หน้าที่:

* trap error แล้วพ่น

  * line number
  * command
  * exit code
* ไม่ต้องเขียน trap ซ้ำหลายไฟล์

---

## B. Command / Dependency helpers

### 7) `require_cmd <cmd>`

### 8) `require_cmds <cmd1> <cmd2> ...`

หน้าที่:

* เช็ก dependency กลาง

ตอนนี้ `need_cmd` ถูกเขียนซ้ำหลาย phase มาก    

---

## C. Retry / Poll / Timeout helpers

### 9) `retry <attempts> <sleep> <command...>`

หน้าที่:

* ใช้ซ้ำกับ cleanup หรือ flaky step

---

### 10) `with_timeout <seconds> <command...>`

หน้าที่:

* wrap timeout แบบทั่วไป

`configure_one.sh` มี function ลักษณะนี้อยู่ใน remote script แล้ว 

---

### 11) `poll_until`

หน้าที่:

* generic loop รอจน predicate ผ่าน
* `openstack_api.sh` จะเอาไปใช้ต่ออีกที

ตัวอย่าง signature:

```bash
poll_until <timeout> <interval> <check_fn> <description>
```

---

## D. File / Path helpers

### 12) `ensure_dir`

### 13) `ensure_parent_dir`

### 14) `safe_copy`

### 15) `safe_move`

หน้าที่:

* ลดการเขียน `mkdir -p` ซ้ำ
* ทำให้การสร้าง manifest/state เป็นมาตรฐาน

---

## E. String / Template helpers

### 16) `render_template_token`

หน้าที่:

* replace `{version}`, `{ts}`, `{vm_name}` อะไรพวกนี้

ตอนนี้ logic แทน template อยู่กระจายใน `preflight.sh`, `create_one.sh`, `publish_one.sh`   

---

### 17) `validate_template_contains_token`

หน้าที่:

* ตรวจว่า template มี token ที่ควรมี
* เช่น VM template ต้องมี `{version}` และ `{ts}`

---

### 18) `extract_first_ipv4`

หน้าที่:

* parse IP ออกจาก string
* ตอนนี้มีซ้ำใน `create_one.sh`, `configure_one.sh`, `clean_one.sh`   

---

## F. SSH / SCP wrappers

ถ้ายังไม่แยก `guest_ssh.sh` ตอนนี้ใส่ไว้ `common_utils.sh` ก่อนได้

### 19) `ssh_run`

### 20) `scp_put`

### 21) `scp_get`

### 22) `wait_ssh_ready`

โค้ดปัจจุบันมี pattern นี้ใน `configure_one.sh` และ `clean_one.sh`  

---

## G. State / Manifest helpers

### 23) `write_flag <path>`

### 24) `clear_flag <path>`

### 25) `set_phase_state <phase> <os> <version> <state>`

หน้าที่:

* เขียน flag files แบบมาตรฐาน

---

### 26) `write_runtime_json`

หน้าที่:

* เขียน JSON state/manifest ให้มีโครงสร้างคงที่

ถ้าจะยังไม่ทำ JSON builder เต็ม
อย่างน้อยควรมี helper ที่รับ file path กับ content template ได้

---

### 27) `write_summary_file`

หน้าที่:

* สร้าง summary มาตรฐานต่อ phase

---

## H. Exit / Result helpers

### 28) `mark_phase_ready`

### 29) `mark_phase_failed`

### 30) `mark_phase_partial`

### 31) `mark_phase_recovered`

หน้าที่:

* ลดการเขียน state/log/result กระจัดกระจายทุก phase

---

# 5) แต่ละ phase จะเรียกยังไง

นี่คือภาพการใช้งานจริง

---

## Import phase

แทนที่จะเขียนทุกอย่างเองในไฟล์ phase

เดิม:

* หา image id
* เช็ก exists
* create
* wait active
* set tags
* write manifest

ควรกลายเป็นประมาณนี้:

```bash id="35y2zh"
require_cmds openstack qemu-img awk grep sed
os_require_auth

disk_format="$(detect_disk_format "$local_path")"
existing_id="$(os_find_image_id_by_name "$image_name")"

case "$ON_EXISTS" in
  skip) ...
  replace) os_delete_image "$existing_id" ;;
  error) ...
esac

image_id="$(os_create_base_image ...)"
os_wait_image_status "$image_id" active "$WAIT_TIMEOUT_SECONDS" "$WAIT_INTERVAL_SECONDS"
os_set_image_tags "$image_id" "$IMAGE_TAGS"
write_runtime_json ...
mark_phase_ready import "$OS_FAMILY" "$VERSION"
```

---

## Create phase

ควรเหลือแค่ orchestration

```bash id="ig2qxt"
require_cmds openstack ssh awk sed
os_require_auth

volume_id="$(os_create_volume_from_image ...)"
os_wait_volume_status "$volume_id" available 600 5

server_id="$(os_create_server_from_volume ...)"
os_wait_server_status "$server_id" ACTIVE 600 5

if [[ -n "$FLOATING_NETWORK" ]]; then
  floating_ip="$(os_allocate_floating_ip "$FLOATING_NETWORK")"
  os_attach_floating_ip "$server_id" "$floating_ip"
fi

write_runtime_json ...
mark_phase_ready create "$OS_FAMILY" "$VERSION"
```

---

## Configure phase

ควรใช้ common utilities เยอะสุด

```bash id="bhq0jp"
require_cmds ssh scp
init_log_file ...
trap_with_context

wait_ssh_ready "$VM_HOST" "$SSH_PORT"
scp_put "$LOCAL_REMOTE_FILE" "$REMOTE_SCRIPT"
ssh_run "$VM_HOST" "$SSH_PORT" "$SSH_USER" "$AUTH_MODE" ...

write_runtime_json ...
mark_phase_ready configure "$OS_FAMILY" "$VERSION"
```

---

## Publish phase

ควรอ่านง่ายขึ้นเยอะ

```bash id="e48c9n"
os_require_auth

if os_final_image_exists_and_active "$FINAL_IMAGE_NAME"; then
  ...
fi

if os_server_exists "$SERVER_ID"; then
  os_delete_server "$SERVER_ID"
  os_wait_volume_status "$VOLUME_ID" available 600 5
fi

final_image_id="$(os_upload_volume_to_image ...)"
os_wait_image_status "$final_image_id" active "$WAIT_FINAL_TIMEOUT_SECONDS" "$WAIT_FINAL_INTERVAL_SECONDS"
os_apply_final_image_metadata "$final_image_id" ...

os_delete_volume_with_retry "$VOLUME_ID" 6
os_delete_image "$BASE_IMAGE_ID"

write_runtime_json ...
mark_phase_ready publish "$OS_FAMILY" "$VERSION"
```

---

# 6) อะไรไม่ควรใส่ใน 2 ไฟล์นี้

## ไม่ควรใส่ใน `openstack_api.sh`

* menu logic
* path logic
* config merge logic
* guest repo/LEGACY_MIRROR logic
* locale/timezone/cloud-init logic
* parsing guest config files

เพราะไฟล์นี้ควรโฟกัสแค่ OpenStack resource operations

---

## ไม่ควรใส่ใน `common_utils.sh`

* OpenStack-specific status names เยอะเกินไป
* คำสั่ง `openstack image create` ตรง ๆ
* guest OS policy เฉพาะ Ubuntu
* logic ของ phase ใด phase หนึ่งโดยเฉพาะ

เพราะไฟล์นี้ต้องเป็นของกลางจริง ๆ

---

# สรุปแบบสั้นที่สุด

## `openstack_api.sh`

ควรมี:

* auth check
* list/show/exists
* create/delete image/volume/server
* wait status image/volume/server
* floating IP
* upload final image
* apply metadata/tags
* cleanup/retry helpers ฝั่ง OpenStack

## `common_utils.sh`

ควรมี:

* log/die/trap
* require commands
* retry/timeout/poll
* template/ip helpers
* ssh/scp wrappers
* flag/json/state writers
* common file helpers

---

# ถ้าจะเริ่มทำจริง “ลำดับดีที่สุด”

ผมแนะนำให้เริ่ม implement ตามนี้

1. `common_utils.sh`

   * log/die/require_cmds/retry/poll/ssh helpers
2. `openstack_api.sh`

   * exists/status/wait/create/delete/upload wrappers
3. refactor `import_one.sh`
4. refactor `create_one.sh`
5. refactor `publish_one.sh`
6. refactor `configure_one.sh`
7. refactor `clean_one.sh`

เพราะ 3 phase แรกจะเห็นผลเรื่องลดโค้ดซ้ำชัดสุด


ได้ อันนี้คือ **Design Spec ระดับ final** สำหรับ
**`lib/common_utils.sh`** และ **`lib/openstack_api.sh`**
แบบเอาไปใช้เป็นสเปกต่อได้เลย โดยยึดจาก pattern ที่มีอยู่ใน phases ปัจจุบัน เช่น import/create/configure/clean/publish ซึ่งตอนนี้มี logic ซ้ำพวก `need_cmd`, logging, wait loops, server/image/volume status checks, SSH helpers, และ `cinder upload-to-image` อยู่กระจัดกระจายแล้ว     

ผมจะสรุปเป็น 7 ส่วน:

1. เป้าหมายของ 2 ไฟล์นี้
2. กติกาการตั้งชื่อฟังก์ชัน
3. กติกา return code กลาง
4. รายการฟังก์ชัน final ของ `common_utils.sh`
5. รายการฟังก์ชัน final ของ `openstack_api.sh`
6. ฟังก์ชันไหน phase ไหนจะใช้
7. ขอบเขตว่าอะไรไม่ควรใส่ใน 2 ไฟล์นี้

---

# 1) เป้าหมายของ 2 ไฟล์นี้

ตอนนี้ phase ต่าง ๆ ทำงานได้ แต่มีปัญหาชัดเจนคือ logic สำคัญกระจายเต็ม repo เช่น

* logging / die / trap
* dependency checks
* polling / timeout / retry
* OpenStack resource exists/status/wait/delete
* SSH/SCP wrappers
* template rendering
* state / manifest writing

ถ้าไม่รวมศูนย์ จะเกิดผลเสียแบบนี้:

* phase ยาวเกิน
* naming ไม่สม่ำเสมอ
* timeout policy คนละแบบ
* bug เดียวต้องแก้หลายไฟล์
* review/AI อ่านยาก

ดังนั้น:

* `common_utils.sh` = ของกลางที่ทุก phase ใช้ได้
* `openstack_api.sh` = ของเฉพาะ OpenStack/Cinder/Nova/Glance

---

# 2) กติกาการตั้งชื่อฟังก์ชัน

เพื่อให้ repo ไม่มั่ว ผมแนะนำให้ใช้ prefix แบบนี้

## ของกลาง

ใช้ prefix:

```text
util_
state_
ssh_
json_
template_
```

ตัวอย่าง:

* `util_log_info`
* `util_require_cmds`
* `util_retry`
* `ssh_wait_ready`
* `state_mark_ready`
* `json_write_file`

## ของ OpenStack

ใช้ prefix:

```text
os_
```

ตัวอย่าง:

* `os_require_auth`
* `os_image_exists`
* `os_wait_image_status`
* `os_create_volume_from_image`
* `os_upload_volume_to_image`

---

# 3) กติกา return code กลาง

ผมแนะนำให้ล็อกเป็นมาตรฐานกลางแบบนี้

## Return code มาตรฐาน

* `0` = success / true / ready
* `1` = generic failure / false
* `2` = invalid argument / bad input
* `3` = missing dependency / command missing
* `4` = auth or environment not ready
* `5` = resource not found
* `6` = resource already exists / conflict
* `7` = timeout
* `8` = resource bad status / state transition failure
* `9` = remote execution failure / SSH failure
* `10` = parse failure / unexpected output
* `11` = retry exhausted
* `12` = cleanup warning / non-fatal cleanup failure

## กฎสำคัญ

ฟังก์ชันควรมี 3 กลุ่มชัดเจน

### กลุ่ม A: boolean functions

เช่น:

* `os_image_exists`
* `os_server_exists`
* `util_file_exists_nonempty`

กติกา:

* `0` = yes/exists
* `1` = no/not exists
* ไม่ควรโยน text เยอะถ้าไม่จำเป็น

### กลุ่ม B: getter functions

เช่น:

* `os_get_image_status`
* `os_get_server_status`
* `os_find_image_id_by_name`

กติกา:

* output ทาง stdout
* `0` = ได้ค่า
* `5` = หาไม่เจอ
* `10` = parse ไม่ได้

### กลุ่ม C: action functions

เช่น:

* `os_create_base_image`
* `os_create_volume_from_image`
* `os_delete_volume_with_retry`

กติกา:

* `0` = สำเร็จ
* non-zero = fail ตามชนิดความผิด
* ควร log ชัดว่า fail ตรงไหน

---

# 4) `lib/common_utils.sh` — Final Function List

อันนี้คือรายการที่ผมแนะนำให้มีจริง

---

## A. Logging / Error / Trap

### 1) `util_log_info`

**Purpose:** log ข้อความทั่วไป
**Args:**

* `$1` = message
  **Stdout/Stderr:** เขียน log ไปยัง stdout และไฟล์ log ถ้ามี
  **Return:** `0`

---

### 2) `util_log_warn`

**Purpose:** log warning
**Args:**

* `$1` = message
  **Return:** `0`

---

### 3) `util_log_error`

**Purpose:** log error
**Args:**

* `$1` = message
  **Return:** `0`

---

### 4) `util_die`

**Purpose:** log error แล้ว exit/return fail
**Args:**

* `$1` = message
* `$2` = optional return code (default `1`)
  **Return:** non-zero

---

### 5) `util_init_log_file`

**Purpose:** เตรียม log file ของ phase ปัจจุบัน
**Args:**

* `$1` = absolute/relative log file path
  **Side effect:**
* export `CURRENT_LOG_FILE`
* create parent dir if needed
  **Return:** `0` หรือ `2`

---

### 6) `util_enable_error_trap`

**Purpose:** ติดตั้ง trap กลางที่ log line/cmd/exit code
**Args:** none
**Return:** `0`

---

### 7) `util_trap_handler`

**Purpose:** handler กลางของ ERR trap
**Args:**

* exit code
* line number
* command
  **Return:** non-zero

---

## B. Command / Dependency

### 8) `util_require_cmd`

**Purpose:** เช็กว่ามีคำสั่งนี้ใน PATH
**Args:**

* `$1` = command name
  **Return:**
* `0` = found
* `3` = missing

---

### 9) `util_require_cmds`

**Purpose:** เช็กหลายคำสั่งทีเดียว
**Args:**

* `$@` = list of commands
  **Return:**
* `0` = ครบ
* `3` = ขาดอย่างน้อยหนึ่งตัว

---

## C. File / Path / Safety

### 10) `util_ensure_dir`

**Purpose:** `mkdir -p` อย่างปลอดภัย
**Args:**

* `$1` = directory path
  **Return:** `0` หรือ `2`

---

### 11) `util_ensure_parent_dir`

**Purpose:** สร้าง parent dir ของไฟล์
**Args:**

* `$1` = file path
  **Return:** `0` หรือ `2`

---

### 12) `util_safe_copy`

**Purpose:** copy file พร้อมสร้าง parent dir ให้ปลายทาง
**Args:**

* `$1` = src
* `$2` = dst
  **Return:** `0` หรือ `1`

---

### 13) `util_safe_move`

**Purpose:** move file พร้อมสร้าง parent dir
**Args:**

* `$1` = src
* `$2` = dst
  **Return:** `0` หรือ `1`

---

### 14) `util_file_exists_nonempty`

**Purpose:** เช็กว่าไฟล์มีและไม่ว่าง
**Args:**

* `$1` = file path
  **Return:**
* `0` = yes
* `1` = no

---

## D. Retry / Poll / Timeout

### 15) `util_retry`

**Purpose:** retry คำสั่งเดิมหลายครั้ง
**Args:**

* `$1` = attempts
* `$2` = sleep seconds
* `$@` ที่เหลือ = command
  **Return:**
* `0` = success
* `11` = retry exhausted
* หรือ return code ล่าสุดของ command ก็ได้ ถ้าจะเก็บรายละเอียด

---

### 16) `util_with_timeout`

**Purpose:** รัน command ภายใต้ timeout
**Args:**

* `$1` = timeout seconds
* `$@` ที่เหลือ = command
  **Return:**
* `0` = success
* `7` = timeout
* `1` = command fail

---

### 17) `util_poll_until`

**Purpose:** generic polling
**Args:**

* `$1` = timeout seconds
* `$2` = interval seconds
* `$3` = description
* `$4...` = command/predicate
  **Return:**
* `0` = predicate ผ่าน
* `7` = timeout
* `1` = predicate fail hard

ใช้กับ:

* SSH ready
* file appears
* state file exists
* generic waits ที่ไม่ใช่ OpenStack status

---

## E. Template / String / Parse Helpers

### 18) `template_render`

**Purpose:** render token ง่าย ๆ เช่น `{version}`, `{ts}`, `{vm_name}`
**Args:**

* `$1` = template string
* `$2...` = `key=value` pairs
  **Stdout:** rendered string
  **Return:** `0` หรือ `2`

---

### 19) `template_require_tokens`

**Purpose:** validate ว่า template มี token ที่ต้องมี
**Args:**

* `$1` = template
* `$@` ที่เหลือ = required tokens
  **Return:**
* `0` = ok
* `2` = token missing

---

### 20) `util_extract_first_ipv4`

**Purpose:** ดึง IPv4 แรกจาก string
**Args:**

* `$1` = raw string
  **Stdout:** first IPv4 or empty
  **Return:**
* `0` = parsed / even empty allowed
* `10` = parse failure only if strict mode needed

ตอนนี้ logic นี้มีซ้ำในหลาย phase แล้ว ควรรวมศูนย์   

---

### 21) `util_csv_to_lines`

**Purpose:** แปลง csv เป็น lines
**Args:**

* `$1` = csv string
  **Stdout:** one item per line
  **Return:** `0`

ใช้กับ:

* tags
* config lists

---

## F. SSH / SCP wrappers

### 22) `ssh_build_opts`

**Purpose:** สร้าง SSH options จาก config
**Args:**

* host
* port
* user
* key path optional
  **Stdout:** options string/array strategy
  **Return:** `0` หรือ `2`

---

### 23) `ssh_run`

**Purpose:** รัน command ผ่าน SSH
**Args:**

* host
* port
* user
* auth_mode (`password|key`)
* auth_value
* remote_command
  **Return:**
* `0` = success
* `9` = remote/ssh failure

pattern นี้ตอนนี้อยู่ใน `configure_one.sh` และ `clean_one.sh`  

---

### 24) `scp_put`

**Purpose:** upload file ไป guest
**Args:**

* host
* port
* user
* auth_mode
* auth_value
* local_path
* remote_path
  **Return:**
* `0` success
* `9` fail

---

### 25) `scp_get`

**Purpose:** download file จาก guest
**Args:**

* host
* port
* user
* auth_mode
* auth_value
* remote_path
* local_path
  **Return:**
* `0` success
* `9` fail

---

### 26) `ssh_wait_ready`

**Purpose:** รอให้ SSH พร้อม
**Args:**

* host
* port
* user
* auth_mode
* auth_value
* timeout
* interval
  **Return:**
* `0` ready
* `7` timeout
* `9` SSH fail

---

## G. State / Flag / JSON helpers

### 27) `state_flag_path`

**Purpose:** คืน path ของ flag file มาตรฐาน
**Args:**

* phase
* os_family
* os_version
* state_name
  **Stdout:** path
  **Return:** `0`

---

### 28) `state_write_flag`

**Purpose:** เขียน flag file
**Args:**

* phase
* os_family
* os_version
* state_name
  **Return:** `0` หรือ `1`

---

### 29) `state_clear_flag`

**Purpose:** ลบ flag file
**Args:**

* phase
* os_family
* os_version
* state_name
  **Return:** `0` หรือ `1`

---

### 30) `state_mark_ready`

**Purpose:** mark phase ready
**Args:**

* phase
* os_family
* os_version
  **Return:** `0`

---

### 31) `state_mark_failed`

**Purpose:** mark phase failed
**Args:**

* phase
* os_family
* os_version
  **Return:** `0`

---

### 32) `state_mark_partial`

**Purpose:** mark partial success
**Args:**

* phase
* os_family
* os_version
  **Return:** `0`

---

### 33) `json_write_file`

**Purpose:** เขียน JSON content ลงไฟล์
**Args:**

* file path
* content string
  **Return:** `0` หรือ `1`

---

### 34) `json_escape`

**Purpose:** escape string ให้ปลอดภัยเวลา generate JSON ใน Bash
**Args:**

* `$1` = raw string
  **Stdout:** escaped string
  **Return:** `0`

---

### 35) `state_write_runtime_json`

**Purpose:** helper กลางในการเขียน runtime JSON ต่อ phase
**Args:**

* phase
* os_family
* os_version
* json payload file/content
  **Return:** `0` หรือ `1`

---

# 5) `lib/openstack_api.sh` — Final Function List

---

## A. Auth / Environment

### 1) `os_require_auth`

**Purpose:** เช็กว่า OpenStack auth พร้อมใช้
**Args:** none
**Command:** `openstack token issue`
**Return:**

* `0` = auth ready
* `4` = auth fail

โค้ดปัจจุบันเรียก `openstack token issue` หลาย phase แล้ว ควรรวมศูนย์   

---

### 2) `os_get_current_project_id`

**Purpose:** ดึง project id ปัจจุบัน
**Args:** none
**Stdout:** project id
**Return:** `0|4|10`

---

### 3) `os_get_project_name`

**Purpose:** ดึง project name จาก id หรือ name
**Args:**

* `$1` = project ref
  **Stdout:** project name
  **Return:** `0|5|10`

---

### 4) `os_validate_expected_project`

**Purpose:** validate ว่า auth อยู่ใน project ที่ถูก
**Args:**

* `$1` = expected project name
  **Return:**
* `0` = match
* `4` = auth fail
* `5` = project not found
* `1` = mismatch

---

## B. Lookup / Discovery สำหรับเมนู

### 5) `os_list_projects`

### 6) `os_list_networks`

### 7) `os_list_flavors`

### 8) `os_list_volume_types`

### 9) `os_list_security_groups`

### 10) `os_list_floating_networks`

**Purpose:** ใช้กับเมนู Settings
**Args:** optional filters
**Stdout:** table/value list ที่ parse ง่าย
**Return:** `0|4|10`

---

## C. Image functions

### 11) `os_find_image_id_by_name`

**Purpose:** หา image id จาก name
**Args:**

* `$1` = image name
  **Stdout:** image id
  **Return:**
* `0` found
* `5` not found
* `10` parse fail

---

### 12) `os_image_exists`

**Purpose:** เช็กว่า image มีอยู่ไหม
**Args:**

* `$1` = image id or name
  **Return:**
* `0` yes
* `1` no

---

### 13) `os_get_image_status`

**Purpose:** ดึง image status
**Args:**

* `$1` = image id
  **Stdout:** status
  **Return:** `0|5|10`

---

### 14) `os_create_base_image`

**Purpose:** import local image เข้า Glance
**Args:**

* image_name
* local_path
* disk_format
* visibility
* os_family
* os_version
* source_release_page
* source_artifact_url
* source_checksum
* tags_csv
  **Stdout:** image id
  **Return:**
* `0` success
* `2` bad args
* `4` auth fail
* `6` conflict exists
* `10` parse fail
* `1` create fail

โค้ดนี้ย้ายมาจาก pattern ใน `import_one.sh` 

---

### 15) `os_delete_image`

**Purpose:** ลบ image
**Args:** image_id
**Return:** `0|5|1`

---

### 16) `os_set_image_tags`

**Purpose:** set tags หลายตัว
**Args:**

* image_id
* csv_tags
  **Return:** `0|5|1`

---

### 17) `os_set_image_properties`

**Purpose:** set property หลายตัว
**Args:**

* image_id
* `key=value...`
  **Return:** `0|5|1`

---

### 18) `os_wait_image_status`

**Purpose:** รอ image เข้า desired status
**Args:**

* image_id
* desired_status
* timeout_seconds
* interval_seconds
  **Return:**
* `0` desired reached
* `5` image missing
* `7` timeout
* `8` bad status
* `10` parse fail

---

## D. Volume functions

### 19) `os_find_volume_id_by_name`

### 20) `os_volume_exists`

### 21) `os_get_volume_status`

เหมือน image แต่สำหรับ volume

---

### 22) `os_create_volume_from_image`

**Purpose:** สร้าง boot volume จาก image
**Args:**

* volume_name
* image_id
* size_gb
* volume_type
  **Stdout:** volume id
  **Return:** `0|2|4|6|10|1`

---

### 23) `os_delete_volume`

**Purpose:** ลบ volume
**Args:** volume_id
**Return:** `0|5|1`

---

### 24) `os_wait_volume_status`

**Purpose:** รอ volume status
**Args:**

* volume_id
* desired_status
* timeout
* interval
  **Return:** `0|5|7|8|10`

---

### 25) `os_wait_volume_deletable`

**Purpose:** รอให้ volume อยู่ในสถานะลบได้
**Args:**

* volume_id
* timeout
* interval
  **Return:** `0|5|7|8`

---

### 26) `os_delete_volume_with_retry`

**Purpose:** ลบ volume แบบ retry
**Args:**

* volume_id
* attempts
* retry_sleep
  **Return:**
* `0` success
* `11` retry exhausted
* `12` cleanup warning ถ้าจะใช้ soft-fail model

pattern นี้ย้ายจาก `publish_one.sh` ตรง ๆ ได้เลย 

---

## E. Server functions

### 27) `os_find_server_id_by_name`

### 28) `os_server_exists`

### 29) `os_get_server_status`

เหมือน resource getters ปกติ

---

### 30) `os_create_server_from_volume`

**Purpose:** สร้าง server จาก boot volume
**Args:**

* server_name
* flavor_id
* network_id
* security_group
* volume_id
* user_data_file
* optional key_name
  **Stdout:** server id
  **Return:** `0|2|4|6|10|1`

ย้ายจาก `create_one.sh` 

---

### 31) `os_delete_server`

**Purpose:** ลบ server
**Args:** server_id
**Return:** `0|5|1`

---

### 32) `os_start_server`

### 33) `os_stop_server`

ไว้ใช้ future recover / clean flow

---

### 34) `os_wait_server_status`

**Purpose:** รอ server status
**Args:**

* server_id
* desired_status
* timeout
* interval
  **Return:** `0|5|7|8|10`

---

### 35) `os_get_server_addresses`

**Purpose:** ดึง raw addresses string
**Args:** server_id
**Stdout:** addresses raw
**Return:** `0|5|10`

---

### 36) `os_get_server_login_ip`

**Purpose:** เลือก login IP จาก addresses/floating/fixed
**Args:**

* server_id
* optional preferred floating ip
  **Stdout:** login ip
  **Return:** `0|5|10`

---

## F. Floating IP

### 37) `os_allocate_floating_ip`

**Purpose:** allocate floating IP
**Args:** floating_network
**Stdout:** IP address
**Return:** `0|4|10|1`

---

### 38) `os_attach_floating_ip`

**Purpose:** attach floating IP ให้ server
**Args:**

* server_id
* floating_ip
  **Return:** `0|5|1`

---

## G. Publish / Final Image

### 39) `os_upload_volume_to_image`

**Purpose:** ทำ `cinder upload-to-image`
**Args:**

* volume_id
* final_image_name
* disk_format
* container_format
* force_flag
  **Stdout:** best-effort image_id or raw upload output
  **Return:**
* `0` upload command success
* `5` volume missing
* `1` upload fail
* `10` parse fail

ย้ายจาก `publish_one.sh` 

---

### 40) `os_find_or_wait_image_id_by_name`

**Purpose:** ถ้า parse image_id จาก upload output ไม่ได้ ให้หาโดย name พร้อมรอ
**Args:**

* image_name
* timeout
* interval
  **Stdout:** image id
  **Return:** `0|5|7|10`

---

### 41) `os_apply_final_image_metadata`

**Purpose:** set visibility, tags, properties สำหรับ final image
**Args:**

* image_id
* visibility
* tags_csv
* os_family
* os_version
* source_server_id
* source_volume_id
* source_base_image_id
  **Return:** `0|5|1`

ย้ายจาก `publish_one.sh` 

---

### 42) `os_final_image_exists_active`

**Purpose:** เช็กว่ามี final image active อยู่แล้วไหม
**Args:**

* final_image_name
  **Stdout:** image id ถ้ามี
  **Return:**
* `0` active exists
* `1` not exists or not active
* `10` parse fail

---

### 43) `os_recover_existing_final_image`

**Purpose:** ใช้ final image เดิมถ้า policy = recover
**Args:**

* final_image_name
* timeout
* interval
  **Stdout:** image id
  **Return:**
* `0` recovered usable final image
* `1` not recoverable
* `7` timeout
* `8` bad status

---

# 6) Phase ไหนจะใช้ฟังก์ชันอะไร

## Import phase

ใช้หลัก ๆ:

* `util_require_cmds`
* `os_require_auth`
* `os_find_image_id_by_name`
* `os_create_base_image`
* `os_wait_image_status`
* `os_set_image_tags`
* `state_write_runtime_json`
* `state_mark_ready`

---

## Create phase

ใช้หลัก ๆ:

* `os_create_volume_from_image`
* `os_wait_volume_status`
* `os_create_server_from_volume`
* `os_wait_server_status`
* `os_allocate_floating_ip`
* `os_attach_floating_ip`
* `os_get_server_login_ip`

---

## Configure phase

ใช้หลัก ๆ:

* `ssh_wait_ready`
* `ssh_run`
* `scp_put`
* `scp_get`
* `util_with_timeout`
* `state_write_runtime_json`
* `state_mark_ready`
* และอาจใช้ `os_get_server_status` ตอน reboot/clean

---

## Clean phase

ใช้หลัก ๆ:

* `ssh_run`
* `ssh_wait_ready`
* `os_wait_server_status`
* `state_mark_ready`

---

## Publish phase

ใช้หลัก ๆ:

* `os_final_image_exists_active`
* `os_delete_server`
* `os_wait_volume_status`
* `os_upload_volume_to_image`
* `os_find_or_wait_image_id_by_name`
* `os_wait_image_status`
* `os_apply_final_image_metadata`
* `os_delete_volume_with_retry`
* `os_delete_image`
* `state_mark_ready` หรือ `state_mark_partial`

---

# 7) อะไรไม่ควรใส่ใน 2 ไฟล์นี้

## ไม่ควรใส่ใน `openstack_api.sh`

* menu logic
* path logic
* guest repo/LEGACY_MIRROR logic
* locale/timezone/cloud-init config
* config merge default/version
* user interaction

## ไม่ควรใส่ใน `common_utils.sh`

* คำสั่ง `openstack image create` โดยตรง
* OpenStack status names ที่เฉพาะเกินไป
* guest policy เฉพาะ Ubuntu
* publish flow orchestration ทั้งก้อน

---

# คำตอบแบบสั้นที่สุด

อันนี้คือ design spec final ที่ผมแนะนำ:

## `common_utils.sh`

เก็บ:

* logging
* die/trap
* require cmds
* retry/timeout/poll
* file/path helpers
* template/ip helpers
* ssh/scp wrappers
* flag/json/state writers

## `openstack_api.sh`

เก็บ:

* auth check
* list/show/exists
* get status
* create/delete image/volume/server
* wait status
* floating ip
* volume upload to image
* apply image metadata
* recovery helpers ของ final image



