import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mycomicbrain/core/design_system/tokens.dart';

/// La cover reale di un'Edizione se nota (percorso locale scaricato da
/// `CopertinaDownloader`, o in fallback l'URL remoto originale), altrimenti
/// [ProceduralComicCover]. Un percorso locale ma ormai mancante su disco
/// ricade sullo stesso segnaposto invece di un errore visibile. Condivisa
/// dal carosello "Aggiunti di recente" (§4.1) e dalla griglia Collezione
/// (§9) — stessa resa, stesso fallback.
class ComicCoverImage extends StatelessWidget {
  const ComicCoverImage({
    required this.coverImage,
    required this.titolo,
    required this.numero,
    required this.etichetta,
    this.compatto = false,
    super.key,
  });

  final String? coverImage;
  final String titolo;

  /// Seme della copertina procedurale di fallback — vedi
  /// [ProceduralComicCover].
  final int numero;
  final String etichetta;

  /// Il testo di [ProceduralComicCover] non entra in celle sotto i ~90px
  /// di larghezza (pensata per griglie tipo Collezione, §9). `true` per un
  /// fallback minimo senza testo — usarlo dove titolo/numero sono già
  /// mostrati a fianco della cover (righe di lista, header), non nelle
  /// griglie dove il testo procedurale è l'unica etichetta della cella.
  final bool compatto;

  @override
  Widget build(BuildContext context) {
    final procedurale = compatto
        ? const _PlaceholderCompatto()
        : ProceduralComicCover(
            titolo: titolo,
            numero: numero,
            etichetta: etichetta,
          );
    final immagine = coverImage;
    if (immagine == null) return procedurale;

    final isRemote =
        immagine.startsWith('http://') || immagine.startsWith('https://');
    final risolta = ClipRRect(
      borderRadius: AppRadii.xsRadius,
      child: isRemote
          ? Image.network(
              immagine,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => procedurale,
            )
          : Image.file(
              File(immagine),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => procedurale,
            ),
    );
    return SizedBox.expand(child: risolta);
  }
}

/// Fallback minimo per [ComicCoverImage.compatto] — nessun testo, solo
/// un'icona, per celle troppo piccole per [ProceduralComicCover].
class _PlaceholderCompatto extends StatelessWidget {
  const _PlaceholderCompatto();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: AppRadii.xsRadius,
      ),
      child: Icon(
        Icons.auto_stories_outlined,
        color: AppColors.textDisabled,
        size: 16,
      ),
    );
  }
}

/// Copertina segnaposto generata dal titolo e dal numero, per le Edizioni
/// senza cover nota (prototipo `cover()`/`shape`): colore di sfondo scelto
/// da `(titolo.length + numero) % palette`, forma (cerchio/quadrato
/// arrotondato) dalla parità del numero, rotazione dal resto modulo 3.
class ProceduralComicCover extends StatelessWidget {
  const ProceduralComicCover({
    required this.titolo,
    required this.numero,
    required this.etichetta,
    super.key,
  });

  final String titolo;
  final int numero;
  final String etichetta;

  static const List<({Color bg, Color ink})> _palette = [
    (bg: Color(0xFF1B3A4B), ink: Color(0xFFEFE7D6)),
    (bg: Color(0xFFB23A2E), ink: Color(0xFFF7E4C8)),
    (bg: Color(0xFF2E2A4F), ink: Color(0xFFE6E2F2)),
    (bg: Color(0xFF0F5C4A), ink: Color(0xFFEAF3E5)),
    (bg: Color(0xFFC4771B), ink: Color(0xFF22160C)),
    (bg: Color(0xFF3A3A3C), ink: Color(0xFFF0F0F2)),
    (bg: Color(0xFF7A2E4E), ink: Color(0xFFF6E1EA)),
    (bg: Color(0xFF1E4620), ink: Color(0xFFE8F0DE)),
  ];

  @override
  Widget build(BuildContext context) {
    final colori = _palette[(titolo.length + numero) % _palette.length];
    final circolare = numero.isOdd;
    final rotazione = ((numero % 3) * 9 - 9) * (math.pi / 180);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colori.bg,
        borderRadius: AppRadii.xsRadius,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -13,
            bottom: -18,
            child: Transform.rotate(
              angle: rotazione,
              child: Container(
                width: 71,
                height: 72,
                decoration: BoxDecoration(
                  color: colori.ink.withValues(alpha: 0.22),
                  shape: circolare ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: circolare ? null : BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titolo,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: colori.ink,
                    height: 1.15,
                  ),
                ),
                const Spacer(),
                if (etichetta.isNotEmpty)
                  Text(
                    etichetta,
                    style: AppTypography.monoLabel.copyWith(color: colori.ink),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
