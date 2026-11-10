# Drawer Maker Pro · SketchUp Workshop

Ekstensi Ruby untuk **SketchUp 2022+**. Versi 1.1 menambah pilihan laci, Smart Box, pintu, dan preset lokal untuk mengikuti alur kabinet pada video referensi. Tidak membutuhkan koneksi internet.

## Fitur

- **Laci kayu, sisi metal, dan gallery rail**: konstruksi 3D berbeda; tipe rail memiliki sisi rendah dengan batang di atasnya, bukan panel penuh.
- **Muka slab, shaker, dan kaca**: bingkai terdiri dari stile/rail terpisah, panel tengah recessed, dan material kaca transparan. Handle memiliki batang dan dua dudukan.
- **Smart Box**: bodi kabinet, plint, sekat vertikal, rak per kolom, serta pintu tunggal/ganda per kolom atau tanpa pintu.
- **Preset lokal**: kayu, metal, rail, shaker, kaca; kabinet bawah, dinding, etalase, lemari penyimpanan. Preset mengisi parameter konstruksi; ukuran ruang tidak berubah.
- **Preview depan/isometrik** dari part yang dihitung kalkulator Ruby yang sama dengan generator model.
- **Edit / Replace Style**: ubah konstruksi, pembagian, handle, serta gaya muka set yang sudah dibuat. Data versi 1.0 tetap dapat dibuka; parameter baru memakai nilai default.
- **Open / Close**: buka/tutup laci atau pintu pada set terpilih, tanpa mengubah ukuran part. Ini pergantian posisi, bukan animasi atau simulasi rel/engsel.
- **Cut List CSV**: ukuran part, jumlah, material; part identik digabung. Termasuk hardware generik, bukan hanya papan.

## Instalasi / update

```sh
bash tools/build_rbz.sh
```

Pasang `dist/drawer_maker_pro.rbz` lewat **Extensions → Extension Manager → Install Extension…**. Untuk update, tutup dan buka kembali SketchUp setelah pemasangan agar seluruh kode baru dimuat. ID ekstensi tetap sama.

Menu dan toolbar: **Drawer Maker Pro**. Buat salinan file `.skp` sebelum mencoba versi baru.

## Alur penggunaan

1. Klik **Smart Box · New Cabinet**. Atur lebar, kedalaman, tinggi, kolom, rak, dan gaya pintu. Kabinet dibuat di origin konteks pengeditan aktif; gunakan Move/Rotate SketchUp untuk menempatkannya.
2. Pilih kabinet → **Insert Drawers** → pilih `Bay … / Space …`. Daftar ruang mengikuti sekat dan rak, bukan seluruh bounding box kabinet.
3. Pilih tipe laci, muka, jumlah, clearance, dan handle → **Buat laci**. Gunakan jumlah kecil untuk ruang pendek; bingkai dan gallery rail memerlukan tinggi minimum.
4. Pilih set kabinet/laci → **Edit / Replace Style** atau **Open / Close**. Keduanya juga ada di menu klik kanan. Edit membangun ulang isi set dan mengembalikannya ke posisi tertutup; edit salinan tidak mengubah set asal.
5. Ekspor CSV lewat **Export Cut List…**.

Untuk kabinet yang tidak dibuat plugin ini, gunakan **Space Tool**: klik dua sudut diagonal bagian dalam bukaan, atau pilih group/komponen kotak ruang lalu **Insert Drawers**. Kotak ruang dipakai sebagai referensi dan tidak dihapus.

### Pembagian ukuran

- `3`: tiga bagian sama besar.
- `1:1:2`: rasio ukuran.
- `200:1:1`: satu bagian 200 mm, sisanya dibagi berdasarkan bobot.
- Angka **lebih besar dari 20** adalah mm tetap; angka 1–20 adalah bobot (atau jumlah jika ditulis sendirian).
- Laci vertikal dibaca atas → bawah; horizontal dan kolom kabinet kiri → kanan.
- Lebar kolom dihitung setelah mengurangi sisi kabinet dan tebal sekat. Rak memakai sisa tinggi setelah dikurangi tebal papan.

## Batasan penting

- Geometri hardware **generik untuk desain**, bukan replika maupun spesifikasi produksi Blum/Hettich. Belum ada groove, drilling, engsel detail, CNC, atau sambungan manufaktur. Verifikasi ukuran produksi dan clearance dengan hardware nyata.
- Sumbu lokal: lebar **X**, kedalaman **+Y**, tinggi **Z**, depan **−Y**. Space Tool memakai sumbu global; pilih kotak ruang dengan orientasi lokal yang benar untuk bukaan berotasi.
- Laci yang dimasukkan ke ruang Smart Box merupakan **set terpisah**. Memindah atau mengubah kabinet tidak otomatis memindah/menyesuaikan lacinya. Pilih keduanya saat memindah; sesuaikan/masukkan ulang laci jika ruang kabinet berubah. Pilih kabinet tanpa pintu untuk laci luar; pintu di depan laci memerlukan clearance tambahan sesuai handle yang dipilih.
- Ukuran luar kabinet dikunci saat edit. Buat kabinet baru untuk ukuran luar berbeda. Jangan memakai Scale non-uniform untuk ukuran produksi: metadata cut list tidak mengikuti perubahan skala manual.
- Preset adalah template lokal, **bukan** katalog aset online. Menu radial dan penggantian model pihak ketiga seperti di video belum tersedia.
- Perubahan manual pada part di dalam set akan hilang saat set dibangun ulang. Cut list memakai ukuran parametrik tersimpan, bukan pengukuran ulang hasil edit manual.

## Verifikasi pengembang

```sh
ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require_relative f }'
npm ci
CHROME_PATH=/usr/local/bin/google-chrome npm run test:ui
bash tools/build_rbz.sh
```

Gunakan Ruby 2.7+ untuk library ekstensi; test development dijalankan dengan Ruby 3.2. Browser test memerlukan Chrome/Chromium lokal (atur `CHROME_PATH`), Node, dan Playwright dari `package-lock.json`. Screenshot ditulis ke `/tmp/verify` atau `DMP_EVIDENCE`.

Tes mencakup geometri, validasi, inset/overlay, bingkai/kaca, ruang antar-rak, builder kabinet, dialog bridge, dan buka/tutup dengan test double SketchUp. Browser menjalankan dialog HTML asli dan memakai kalkulator Ruby untuk preview. **Ini tidak menggantikan pengujian native SketchUp**; loading ekstensi, geometri SketchUp, picking, Undo, material kaca, dan transformasi pintu/laci tetap perlu diuji di aplikasi desktop.
