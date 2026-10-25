import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store.dart';
import 'ui.dart';
import 'world.dart';

const _source = 'https://github.com/Eylexander/pangea';
const _repo = 'https://eylexander.github.io/fdroid/repo';

/// Settings, progress and credits.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _channel = MethodChannel('pangea/app');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final store = Store.instance;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
            children: [
              Row(
                children: [
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: tr('Back', 'Retour'),
                  ),
                  const SizedBox(width: 4),
                  Text(tr('Settings', 'Réglages'), style: display(24)),
                ],
              ),
              _Section(tr('Game', 'Jeu'), [
                _Row(
                  Icons.speed_rounded,
                  tr('Difficulty', 'Difficulté'),
                  subtitle: switch (store.difficulty) {
                    Difficulty.easy => tr('The 70 best-known countries', 'Les 70 pays les plus connus'),
                    Difficulty.normal => tr('145 countries, no tiny islands', '145 pays, sans les petites îles'),
                    Difficulty.hard => tr(
                      'All 197, island states and microstates more often',
                      'Les 197, îles et micro-États plus souvent',
                    ),
                  },
                  below: Segmented(
                    values: Difficulty.values,
                    label: (d) => d.label,
                    selected: store.difficulty,
                    onChanged: (d) => store.difficulty = d,
                  ),
                ),
                _Row(
                  Icons.translate_rounded,
                  tr('Language', 'Langue'),
                  below: Segmented<String?>(
                    values: const [null, 'en', 'fr'],
                    label: (l) => l == null ? tr('Phone', 'Téléphone') : (l == 'en' ? 'English' : 'Français'),
                    selected: store.languageSetting,
                    onChanged: (l) => store.languageSetting = l,
                  ),
                ),
                _Row(
                  Icons.contrast_rounded,
                  tr('Theme', 'Thème'),
                  below: Segmented(
                    values: const ['system', 'light', 'dark'],
                    label: (t) => switch (t) {
                      'light' => tr('Light', 'Clair'),
                      'dark' => tr('Dark', 'Sombre'),
                      _ => tr('Phone', 'Téléphone'),
                    },
                    selected: store.theme,
                    onChanged: (t) => store.theme = t,
                  ),
                ),
              ]),
              _Section(tr('Your progress', 'Ta progression'), [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      _Stat('${store.known.length}', tr('countries\nfound', 'pays\ntrouvés')),
                      _Stat('${store.bestStreak}', tr('best daily\nstreak', 'meilleure\nsérie')),
                      _Stat('${store.dailyWon}/${store.dailyPlayed}', tr('mystery\ncountries', 'pays\nmystère')),
                      _Stat('${store.tripsPerfect}/${store.tripsDone}', tr('perfect\ntrips', 'trajets\nparfaits')),
                    ],
                  ),
                ),
                _Row(
                  Icons.restart_alt_rounded,
                  tr('Reset progress', 'Remettre à zéro'),
                  subtitle: tr('Scores, found countries, streak', 'Scores, pays trouvés, série'),
                  color: bad,
                  onTap: () => _confirmReset(context),
                ),
              ]),
              _Section(tr('About', 'À propos'), [
                FutureBuilder(
                  future: _channel.invokeMethod<String>('version'),
                  builder: (context, v) => _Row(
                    Icons.info_outline_rounded,
                    'Pangea ${v.data ?? ''}',
                    subtitle: tr(
                      'A geography game by Eylexander. Free, offline, no ads, no tracking.',
                      'Un jeu de géographie par Eylexander. Libre, hors ligne, sans pub ni pistage.',
                    ),
                  ),
                ),
                _Row(
                  Icons.code_rounded,
                  tr('Source code', 'Code source'),
                  subtitle: _source.replaceFirst('https://', ''),
                  trailing: Icons.copy_rounded,
                  onTap: () => _copy(context, _source),
                ),
                _Row(
                  Icons.storefront_rounded,
                  tr('Updates (F-Droid repository)', 'Mises à jour (dépôt F-Droid)'),
                  subtitle: _repo.replaceFirst('https://', ''),
                  trailing: Icons.copy_rounded,
                  onTap: () => _copy(context, _repo),
                ),
                _Row(
                  Icons.public_rounded,
                  tr('Earth imagery', 'Images de la Terre'),
                  subtitle: tr(
                    'NASA Blue Marble, July 2004 (public domain)',
                    'NASA Blue Marble, juillet 2004 (domaine public)',
                  ),
                ),
                _Row(
                  Icons.border_style_rounded,
                  tr('Borders and countries', 'Frontières et pays'),
                  subtitle: tr('Natural Earth (public domain)', 'Natural Earth (domaine public)'),
                ),
                _Row(
                  Icons.text_fields_rounded,
                  tr('Font', 'Police'),
                  subtitle: 'Plus Jakarta Sans (SIL Open Font License)',
                ),
                _Row(
                  Icons.flag_outlined,
                  tr('Flags', 'Drapeaux'),
                  subtitle: tr('Your phone\'s emoji', 'Les emoji de ton téléphone'),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  tr(
                    'Borders follow Natural Earth\'s view of the world; some are disputed.',
                    'Les frontières suivent Natural Earth ; certaines sont contestées.',
                  ),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Link copied', 'Lien copié'))));
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Reset your progress?', 'Remettre ta progression à zéro ?')),
        content: Text(
          tr(
            'Records, found countries, the daily streak and road trip stats will be erased. Settings stay.',
            'Les records, pays trouvés, la série et les stats de road trip seront effacés. Les réglages restent.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel', 'Annuler'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: bad),
            child: Text(tr('Reset', 'Effacer')),
          ),
        ],
      ),
    );
    if (ok == true) await Store.instance.resetProgress();
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            decoration: panel(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, c) in children.indexed) ...[
                  if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
                  c,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.title, {this.subtitle, this.below, this.trailing, this.onTap, this.color});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? below;
  final IconData? trailing;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: color ?? cs.onSurfaceVariant),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color),
                      ),
                      if (subtitle != null)
                        Text(subtitle!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35)),
                    ],
                  ),
                ),
                if (trailing != null) Icon(trailing, size: 18, color: cs.onSurfaceVariant),
              ],
            ),
            if (below != null) ...[
              const SizedBox(height: 12),
              Padding(padding: const EdgeInsets.only(left: 36), child: below!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: display(20)),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11.5,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
