# sketchup-cloud-plugin
Cloud-based SketchUp 2022 plugin - katalog model &amp; props, generator drawer/cabinet semi-otomatis, floor plan master, penyimpanan Google Drive

## Drawer Maker Pro

Generator laci parametrik untuk SketchUp 2022+ (`src/drawer_maker_pro`).

### Fitur
- **Space Tool** – klik sudut dalam depan-bawah-kiri lalu sudut belakang-atas-kanan bukaan kabinet. Atau pilih satu group/komponen "ruang" lalu jalankan *Insert Drawers* (ukuran diambil dari bounding box-nya).
- **Dialog Drawer** – Layout Vertical/Horizontal, Quantity, Drawer Depth, Board/Front Thickness, Gap, Bottom Thickness/Raise, clearance rel (slide), front Inset/Overlay, handle (bar / handle-free gola / none), dengan preview tampak depan yang live.
- **Format Quantity** – `3` = 3 laci sama tinggi; `1:1:2` = perbandingan; `200:1:1` = angka > 20 dianggap ukuran tetap (mm), sisanya dibagi rata. Urutan ditulis dari atas ke bawah (vertical) atau kiri ke kanan (horizontal).
- **Geometri** – tiap laci = group berisi Front, Side L/R, Sub Front, Back, Bottom (+ Handle), dengan material terpisah.
- **Edit ulang** – pilih set laci → klik kanan *Edit Drawer Set* (parameter tersimpan di atribut model).
- **Export Cut List** – CSV (panjang × lebar × tebal, qty, material) dari semua part di model.

### Install
```bash
tools/build_rbz.sh   # menghasilkan dist/drawer_maker_pro.rbz
```
Di SketchUp: *Extensions → Extension Manager → Install Extension…* → pilih `drawer_maker_pro.rbz`. Menu ada di *Extensions → Drawer Maker Pro* dan toolbar *Drawer Maker Pro*.

Model harus menghadap depan ke arah −Y (standar SketchUp: tampak Front melihat ke +Y), lebar = X, tinggi = Z.

### Test
```bash
ruby test/calculator_test.rb
```
