# Drawer Maker Pro · SketchUp Workshop

Ekstensi Ruby untuk **SketchUp 2022+ (Windows/macOS, Pro dengan Dynamic Components)**. Versi 1.2 menyusun kabinet dan laci berdasarkan aturan produksi umum sistem frameless 32 mm: fit engsel, sambungan bodi, panel belakang, rel standar, edge banding, dan pegangan handleless. Tidak membutuhkan koneksi internet.

## Fitur

**Kabinet (Smart Box)**
- **Tipe** base / wall / tall. Alas: plint (rangka 4 papan) / kaki adjustable + plint depan / tanpa alas. Kabinet atas mendapat gantungan (hanger).
- **Sambungan bodi**: minifix + dowel, confirmat 7x50, dowel ø8x30, atau rumah (dado). Konektor dimodelkan dan dihitung di BOM; posisi 50 mm dari tepi, maks. 300 mm antar konektor. Dado menambah panjang potong panel horizontal.
- **Panel belakang**: alur (groove), sponing (rabbet), atau dipaku di belakang. Ukuran panel belakang dan kedalaman panel lain mengikuti metode yang dipilih.
- **Atas penuh atau dua rail** (umum untuk kabinet bawah dapur).
- **Kolom** dengan sekat, dan **isi tiap kolom** lewat `bay_fronts`: `door`, `door1`, `door2`, `open`, `drawers:3`, `drawers:1:1:2` (alias: `pintu`, `terbuka`, `laci:3`).
- **Rak** adjustable (pen ø5 di garis 37 mm, celah 1 mm per sisi) atau tetap (disambung seperti panel bodi).

**Pintu & engsel**
- **Fit**: full overlay, half overlay, atau inset; menentukan ukuran dan posisi pintu.
- Pada full overlay, tepi pintu di sekat otomatis berbagi sekat dan memakai **engsel half overlay (crank 9,5)**; tepi di sisi luar memakai **full overlay (crank 0)**; inset memakai **crank 18**.
- Cup ø35 dalam 13 mm di pintu (jarak bor 3–7 mm), mounting plate di garis 37 mm (+ tebal pintu untuk inset). Jumlah engsel menurut tinggi pintu: ≤900 = 2, ≤1600 = 3, ≤2000 = 4, selebihnya 5.

**Pegangan & handleless**
- Bar (c-c), knob, push-open (latch), **gola** (profil L di atas dengan notch pada sisi, profil C di antara laci), **J-pull** (profil J pada tepi muka), **shark tooth** (bevel 45° di belakang tepi), dan **profil aluminium tepi**.
- Tepi pegangan otomatis: kabinet bawah = atas, kabinet atas = bawah, lemari tinggi = sisi bebas. Bisa diatur manual.
- J-pull, shark tooth, dan profil tepi memerlukan muka slab. Tepi berprofil tidak diberi edge banding.

**Laci**
- Rel ball bearing (12,7 mm/sisi), roller (12,5), undermount soft-close (5 mm/sisi, dasar dinaikkan 13 mm), atau custom. Panjang rel standar 250–650 mm otomatis atau manual.
- Kotak kayu, metal box, atau gallery rail. Sambungan depan/belakang butt atau dado. Dasar dalam alur (ukuran + kedalaman alur) atau dipaku di bawah.
- Bagian rel kabinet tetap di bodi; bagian rel laci ikut bergerak.

**Dynamic Component, preview, dan cut list**
- **Setiap pintu dan laci adalah Dynamic Component**: buka/tutup dengan **Interact Tool** (ikon tangan). Pintu berputar di tepi engsel; laci bergeser sepanjang rel. **Tutup semua pintu & laci** mengembalikan set ke posisi tertutup.
- **Preview depan/isometrik** dari part kalkulator yang sama dengan generator model (profil ditampilkan sebagai kotak pembatas).
- **Edit / Replace Style** membangun ulang set dengan parameter baru.
- **Cut list CSV produksi**: ukuran jadi dan **ukuran potong setelah edge banding**, kode edge banding L1/L2/W1/W2, arah serat, BOM hardware (engsel per tipe crank, plate, rel per NL, konektor, pen rak, kaki, profil gola dengan total panjang), serta total edge banding per ketebalan.

## Instalasi / update

```sh
bash tools/build_rbz.sh
```

Pasang `dist/drawer_maker_pro.rbz` lewat **Extensions → Extension Manager → Install Extension…**, lalu **restart SketchUp**. Buat salinan file `.skp` sebelum mencoba versi baru. Pastikan ekstensi **Dynamic Components** aktif agar Interact Tool tersedia.

## Alur penggunaan

1. **Smart Box · New Cabinet** → pilih preset (Kabinet bawah dapur, Kabinet laci, Kabinet atas, Lemari tinggi, Etalase kaca), atur ukuran dan konstruksi → **Buat kabinet**.
2. Buka/tutup pintu & laci dengan **Interact Tool**.
3. Pilih set → klik kanan **Edit / Replace Style** untuk mengubah fit, engsel, sambungan, atau pegangan.
4. Untuk kabinet lain, gunakan **Space Tool** atau pilih kabinet Smart Box → **Insert Drawers** (laci menjadi set terpisah).
5. **Export Cut List…**.

### Pembagian ukuran

- `3`: tiga bagian sama besar; `1:1:2`: rasio; `200:1:1`: 200 mm tetap, sisanya dibagi bobot.
- Angka **lebih besar dari 20** adalah mm tetap; angka 1–20 adalah bobot (atau jumlah jika ditulis sendirian).
- Laci vertikal dibaca atas → bawah; kolom kiri → kanan. Lebar kolom dihitung setelah dikurangi sisi dan sekat.

## Batasan penting

- Nilai produksi adalah **aturan umum workshop**, bukan katalog Blum/Hettich tertentu. Cocokkan clearance rel, crank engsel, dan posisi bor dengan hardware yang dipakai sebelum produksi.
- Alur, sponing, rumah, dan lubang bor **tidak dibor/dipotong pada geometri**; ukurannya masuk ke ukuran potong dan BOM. Panel yang masuk rumah/alur tampak tumpang tindih di model. Notch gola pada sisi dimodelkan.
- Profil gola C dipasang di antara panel bodi (dengan bracket), tidak memotong sisi.
- Animasi Interact bergantung pada ekstensi Dynamic Components. Kabinet hasil salinan (copy) berbagi definisi pintu/laci, sehingga pintu pada salinan dapat ikut bergerak bersama; edit salah satunya dengan **Edit / Replace Style** untuk memisahkannya.
- Laci hasil **Insert Drawers** tetap set terpisah; gunakan `bay_fronts` agar laci menjadi bagian kabinet.
- Ukuran luar kabinet dikunci saat edit. Hindari Scale non-uniform: cut list memakai ukuran parametrik tersimpan.
- Perubahan manual di dalam set hilang saat set dibangun ulang. Menu radial dan katalog online belum tersedia.

## Verifikasi pengembang

```sh
ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require_relative f }'
npm ci
CHROME_PATH=/usr/local/bin/google-chrome npm run test:ui
bash tools/build_rbz.sh
```

Tes Ruby memakai test double SketchUp; browser test menjalankan dialog HTML asli dengan kalkulator Ruby untuk preview. **Ini tidak menggantikan pengujian di SketchUp desktop**: geometri, Interact Tool, Undo, dan material perlu dicek di aplikasi.
