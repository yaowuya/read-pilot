import 'package:flutter/material.dart';

/// Uses the finalized launcher artwork for every in-app brand mark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    image: true,
    label: '阅读标志',
    child: ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .22),
        child: Image.asset(
          'assets/branding/icon-master.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    ),
  );
}
