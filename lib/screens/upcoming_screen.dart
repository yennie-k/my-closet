import 'package:flutter/material.dart';

import '../widgets/common.dart';

class UpcomingScreen extends StatelessWidget {
  const UpcomingScreen({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.feature,
    required this.detail,
  });
  final IconData icon;
  final String eyebrow, title, description, feature, detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(eyebrow: eyebrow, title: title, description: description),
      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity,
        child: SurfaceCard(
          child: Column(
            children: [
              const SizedBox(height: 44),
              Container(
                padding: const EdgeInsets.all(34),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Icon(
                  icon,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 28),
              const ComingSoonBadge(),
              const SizedBox(height: 20),
              Text(
                '$feature 기능을 준비하고 있어요',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(detail, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 44),
            ],
          ),
        ),
      ),
    ],
  );
}
