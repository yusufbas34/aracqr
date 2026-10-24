# Araç QR askılı kutu · matbaa dosyaları

Yazılar **eğriye çevrilmiş** (convert to outlines) PDF'ler; matbaada yazı tipi gerekmez.

- **1. sayfa:** baskı, 2 mm taşma paylı, kesim çizgisi yok
- **2. sayfa:** bıçak / kesim çizgisi (düz = kesim, kesikli = katlama, pembe #EC008C)
- Sayfa = kutu açılımı + her kenarda 4 mm, %100 ölçek
- Önerilen kâğıt: 300–350 g/m² bristol / kuşe karton, isteğe bağlı mat selefon

| Dosya | Sticker / kart | Sayfa (mm) | Kutu iç ölçü (mm) |
|---|---|---|---|
| `aracqr-kutu-40x60-matbaa.pdf` | 4×6 cm | 118 × 114 | 44 × 64 × 6 |
| `aracqr-kutu-50x75-matbaa.pdf` | 5×7,5 cm | 138 × 129 | 54 × 79 × 6 |
| `aracqr-kutu-55x85-matbaa.pdf` | 5,5×8,5 cm (kartvizit) | 148 × 139 | 59 × 89 × 6 |
| `aracqr-kutu-60x90-matbaa.pdf` | 6×9 cm (standart) | 158 × 144 | 64 × 94 × 6 |
| `aracqr-kutu-74x105-matbaa.pdf` | 7,4×10,5 cm (A7) | 186 × 159 | 78 × 109 × 6 |
| `aracqr-kutu-80x120-matbaa.pdf` | 8×12 cm | 198 × 174 | 84 × 124 × 6 |
| `aracqr-kutu-a4-60x90.pdf` | 6×9 cm | A4, 2 kutu | evde yazdırıp elle kesmek için |

Yeniden üretme: `kutu.html?matbaa=1&size=60x90` Chromium'da sayfa ölçüsünde PDF'e basılır, sonra Ghostscript ile yazılar eğriye çevrilir:
`gs -o cikti.pdf -sDEVICE=pdfwrite -dNoOutputFonts -dPDFSETTINGS=/prepress girdi.pdf`
