import 'package:flutter/material.dart';

/// Plezy+: [text] as a span in which every '★' is amber, the colour of the
/// viewer's own rating everywhere in the app.
InlineSpan starTintedSpan(String text) {
  if (!text.contains('★')) return TextSpan(text: text);
  final pieces = text.split('★');
  return TextSpan(
    children: [
      for (var i = 0; i < pieces.length; i++) ...[
        if (i > 0) const TextSpan(text: '★', style: TextStyle(color: Colors.amber)),
        if (pieces[i].isNotEmpty) TextSpan(text: pieces[i]),
      ],
    ],
  );
}
