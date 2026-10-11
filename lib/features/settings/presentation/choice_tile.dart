import 'package:flutter/material.dart';

/// A setting with a few fixed choices. The whole row opens them, not just the
/// value at the end of it.
class ChoiceTile<T> extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String title;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  Future<void> _choose(BuildContext context) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final entry in choices.entries)
            ListTile(
              title: Text(entry.value),
              trailing: entry.key == value ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(entry.key),
            ),
        ],
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(choices[value] ?? '$value'),
        const Icon(Icons.arrow_drop_down),
      ],
    ),
    onTap: () => _choose(context),
  );
}
