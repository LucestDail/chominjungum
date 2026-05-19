import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/jammin_typography.dart';

/// AppBar용 초민정음 로고 + 제목.
class JamminBrandTitle extends StatelessWidget {
  const JamminBrandTitle({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/images/navbar-logo.svg',
          height: 36,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            subtitle,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: JamminTypography.family,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.04,
            ),
          ),
        ),
      ],
    );
  }
}
