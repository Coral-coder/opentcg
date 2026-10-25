import 'package:flutter/material.dart';
import 'package:pokemon/pokemon.dart';
import 'package:tcg_app/tcg_app.dart';

import 'pokemon_theme.dart';

/// The card's image URL: the small scan for the table, the large one when [large].
String pokemonImage(PCard card, {bool large = false}) {
  final url = card.image;
  if (url.isEmpty || large) return url;
  return url.replaceFirst('_hires.png', '.png');
}

/// A Pokémon card: its scan, or a frame drawn from its text while the scan loads or when it
/// can't.
class PokemonCardView extends StatelessWidget {
  const PokemonCardView({super.key, required this.card, this.width = 120, this.large = false});
  final PCard card;
  final double width;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final h = width * 88 / 63;
    final url = pokemonImage(card, large: large);
    final frame = PokemonTextFrame(card: card, width: width);
    return SizedBox(
      width: width,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.05),
        child: url.isEmpty ? frame : Image.network(url, fit: BoxFit.contain, loadingBuilder: (context, child, progress) => progress == null ? child : frame, errorBuilder: (context, e, st) => frame),
      ),
    );
  }
}

/// A plain card frame: name, HP, type and the attacks, in the type's color.
class PokemonTextFrame extends StatelessWidget {
  const PokemonTextFrame({super.key, required this.card, required this.width});
  final PCard card;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final type = card.types.isEmpty ? (card.isTrainer ? null : card.energyType) : card.types.first;
    final c = type == null ? const Color(0xFFB9C3CC) : typeColors[type]!;
    final fs = (width * 0.085).clamp(7.0, 14.0);
    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(c, Colors.white, 0.55),
        border: Border.all(color: const Color(0xFFF5D547), width: width * 0.04),
        borderRadius: BorderRadius.circular(width * 0.05),
      ),
      padding: EdgeInsets.all(width * 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.style(fs, weight: FontWeight.w900),
                ),
              ),
              if (card.hp > 0)
                Text(
                  '${card.hp}',
                  style: t.style(fs, weight: FontWeight.w900, color: t.danger),
                ),
              if (type != null) ...[const SizedBox(width: 2), TypePip(type, size: fs * 1.3)],
            ],
          ),
          Text(
            card.isPokemon ? (card.stage == Stage.basic ? 'Basic' : (card.stage == Stage.stage1 ? 'Stage 1' : 'Stage 2')) : (card.isTrainer ? (card.trainer?.name ?? 'Trainer') : 'Energy'),
            style: t.style(fs * 0.75, color: t.muted),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              [
                for (final a in card.abilities) '${a.name}: ${a.text}',
                for (final a in card.attacks) '${a.name} ${a.damage > 0 ? '${a.damage}${a.mod}' : ''}${a.text.isEmpty ? '' : ' — ${a.text}'}',
                if (card.text.isNotEmpty) card.text,
              ].join('\n'),
              overflow: TextOverflow.fade,
              style: t.style(fs * 0.8, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's game text, readable: abilities, attacks with costs and damage, Weakness,
/// Resistance and Retreat, or a Trainer's effect.
class PokemonCardText extends StatelessWidget {
  const PokemonCardText({super.key, required this.card});
  final PCard card;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final kind = card.isPokemon
        ? '${card.stage == Stage.basic ? 'Basic' : (card.stage == Stage.stage1 ? 'Stage 1' : 'Stage 2')} Pokémon${card.ex ? ' ex' : ''}${card.evolvesFrom == null ? '' : ' · evolves from ${card.evolvesFrom}'}'
        : (card.isTrainer
              ? 'Trainer · ${switch (card.trainer) {
                  TrainerKind.item => 'Item',
                  TrainerKind.supporter => 'Supporter',
                  TrainerKind.stadium => 'Stadium',
                  TrainerKind.tool => 'Pokémon Tool',
                  null => '',
                }}'
              : (card.basicEnergy ? 'Basic Energy' : 'Special Energy'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(card.name, style: t.display(22, weight: FontWeight.w800)),
            ),
            if (card.hp > 0)
              Text(
                'HP ${card.hp}',
                style: t.style(16, weight: FontWeight.w900, color: t.danger),
              ),
            for (final ty in card.types) Padding(padding: const EdgeInsets.only(left: 4), child: TypePip(ty, size: 20)),
          ],
        ),
        Text(kind, style: t.small),
        for (final a in card.abilities) ...[
          const SizedBox(height: 8),
          Text(
            'Ability: ${a.name}',
            style: t.style(14, weight: FontWeight.w800, color: t.danger),
          ),
          Text(a.text, style: t.style(13, weight: FontWeight.w500)),
        ],
        for (final a in card.attacks) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              for (final c in a.cost) Padding(padding: const EdgeInsets.only(right: 2), child: TypePip(c, size: 16)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(a.name, style: t.style(14, weight: FontWeight.w800)),
              ),
              if (a.damage > 0) Text('${a.damage}${a.mod}', style: t.style(16, weight: FontWeight.w900)),
            ],
          ),
          if (a.text.isNotEmpty) Text(a.text, style: t.style(13, weight: FontWeight.w500)),
        ],
        if (card.text.isNotEmpty) ...[const SizedBox(height: 8), Text(card.text, style: t.style(13, weight: FontWeight.w500))],
        for (final r in card.rules) ...[
          const SizedBox(height: 6),
          Text(
            r,
            style: t.style(12, weight: FontWeight.w500, color: t.muted),
          ),
        ],
        if (card.isPokemon) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Weakness ', style: t.small),
                  if (card.weakness != null) ...[TypePip(card.weakness!, size: 14), Text(' ×2', style: t.small)] else Text('—', style: t.small),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Resistance ', style: t.small),
                  if (card.resistance != null) ...[TypePip(card.resistance!, size: 14), Text(' −${card.resistanceAmount}', style: t.small)] else Text('—', style: t.small),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Retreat ', style: t.small),
                  for (var i = 0; i < card.retreat; i++) const TypePip(PType.colorless, size: 14),
                  if (card.retreat == 0) Text('free', style: t.small),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The back of a card (Prize cards, face-down Pokémon during setup): an original design.
class PokemonCardBack extends StatelessWidget {
  const PokemonCardBack({super.key, this.width = 120});
  final double width;
  @override
  Widget build(BuildContext context) {
    final h = width * 88 / 63;
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.05),
        border: Border.all(color: const Color(0xFFFFCB05), width: width * 0.04),
        gradient: const RadialGradient(colors: [Color(0xFF5BA7F0), Color(0xFF1E4E9C)], radius: 0.9),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.star_rounded, size: width * 0.5, color: const Color(0xFFFFCB05)),
    );
  }
}
