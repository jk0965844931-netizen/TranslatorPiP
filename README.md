# TranslatorPiP

แอพแปลเสียงหน้าจอแบบ Real-time พร้อม Picture-in-Picture สำหรับ iPhone

## คุณสมบัติ

- **จับเสียงจาก Screen Recording** — ไม่ต้องการไมโครโฟน ใช้ ReplayKit จับ audio ของแอพอื่น (เช่น YouTube, Netflix, Zoom)
- **แปลเสียงในเครื่อง (On-device)** — ใช้ Apple Speech framework + Translation framework (iOS 17.4+) ทำงานโดยไม่ต้องเชื่อมต่ออินเทอร์เน็ต
- **แสดงผลแบบ PiP** — หน้าต่างแปลลอยอยู่เหนือทุกแอพ ขยับได้อิสระ
- **รองรับหลายภาษา** — EN, TH, JA, ZH, KO, FR, DE, ES

## ความต้องการ

- iOS 17.0+
- iPhone (ไม่รองรับ iPad PiP แบบ video call)

## วิธี Build

### ผ่าน GitHub Actions (แนะนำ)

1. Fork หรือ Push repository นี้ขึ้น GitHub
2. ไปที่ **Actions** tab
3. รัน workflow **"Build Unsigned IPA"**
4. ดาวน์โหลด IPA จาก **Artifacts** หลัง build สำเร็จ

### Build เองบน Mac

```bash
# ติดตั้ง xcodegen
brew install xcodegen

# สร้าง Xcode project
xcodegen generate

# Build
xcodebuild \
  -project TranslatorPiP.xcodeproj \
  -scheme TranslatorPiP \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

# Pack เป็น IPA
mkdir Payload
cp -r build/Release-iphoneos/TranslatorPiP.app Payload/
zip -r TranslatorPiP_unsigned.ipa Payload/
```

## วิธีติดตั้ง IPA (Sideload)

### วิธีที่ 1: AltStore (แนะนำ ไม่ต้องลงทะเบียน)
1. ติดตั้ง [AltStore](https://altstore.io) บน Mac/PC
2. ติดตั้ง AltStore บน iPhone ผ่าน AltServer
3. ลาก `TranslatorPiP_unsigned.ipa` เข้า AltStore
4. แอพจะหมดอายุทุก 7 วัน (ต้อง refresh ผ่าน AltStore)

### วิธีที่ 2: Sideloadly
1. ดาวน์โหลด [Sideloadly](https://sideloadly.io)
2. เชื่อมต่อ iPhone ผ่าน USB
3. ลาก IPA เข้า Sideloadly แล้วกด Start

### วิธีที่ 3: TrollStore (iPhone ที่ jailbreak หรือ exploit ได้)
ลาก IPA เข้า TrollStore ได้เลย ไม่หมดอายุ

## วิธีใช้งาน

1. เปิดแอพ **TranslatorPiP**
2. เลือกภาษาต้นฉบับ (ซ้าย) และภาษาปลายทาง (ขวา)
3. กด **"เริ่มแปลเสียง"**
4. ระบบจะขอสิทธิ์ **Screen Recording** — กด Allow
5. เปิดแอพที่ต้องการแปลเสียง (YouTube, Zoom, Netflix ฯลฯ)
6. หน้าต่าง PiP จะลอยอยู่บนหน้าจอพร้อมคำแปล real-time
7. กด **"เปิด PiP"** เพื่อควบคุมหน้าต่างแปล

## สถาปัตยกรรม

```
ScreenAudioCapture (ReplayKit)
        ↓
SpeechRecognizer (Apple Speech — on-device)
        ↓
TranslationService (Translation framework iOS 17.4+ / fallback MyMemory)
        ↓
PiPManager (AVPictureInPictureController)
        ↓
PiPOverlayViewController (คำแปลลอยบนหน้าจอ)
```

## หมายเหตุ

- **Translation framework** ต้องการ iOS 17.4+ สำหรับ on-device translation
- iOS 17.0–17.3 จะใช้ MyMemory API (ต้องการอินเทอร์เน็ต) เป็น fallback
- ReplayKit จะแสดง banner "Recording" บนหน้าจอ — เป็นข้อจำกัดของ iOS
- unsigned IPA มีอายุ 7 วัน (AltStore/Sideloadly) หรือไม่จำกัด (TrollStore)
