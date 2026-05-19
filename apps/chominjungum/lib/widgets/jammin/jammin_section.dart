import 'package:flutter/material.dart';

import '../../theme/jammin_typography.dart';

/// jammin `.section-heading` + `.section-subheading`.
class JamminSectionHeader extends StatelessWidget {
  const JamminSectionHeader({
    super.key,
    required this.heading,
    this.subheading,
    this.center = true,
  });

  final String heading;
  final String? subheading;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          heading.toUpperCase(),
          textAlign: align,
          style: JamminTypography.sectionHeading(context),
        ),
        if (subheading != null) ...[
          const SizedBox(height: 8),
          Text(
            subheading!,
            textAlign: align,
            style: JamminTypography.sectionSubheading(context),
          ),
        ],
      ],
    );
  }
}
