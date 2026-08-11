import 'package:flutter/material.dart';
import 'package:studyflow/features/ai/ai_repository.dart';

/// Displays L1 AI recommendations without ever mutating tasks or schedule
/// blocks. Any applied change must go through the normal user-confirmed flow.
final class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({
    required this.request,
    super.key,
  });

  /// Returns the next recommendation; throws [AiApiFailure] on error.
  final Future<AiRecommendation> Function() request;

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

final class _RecommendationScreenState extends State<RecommendationScreen> {
  AiRecommendation? _recommendation;
  Object? _error;
  bool _loading = false;

  Future<void> _request() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recommendation = await widget.request();
      if (!mounted) {
        return;
      }
      setState(() {
        _recommendation = recommendation;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = _recommendation;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Recommendations')),
      body: RefreshIndicator(
        onRefresh: _request,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (_error != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Recommendation unavailable'),
                  subtitle: Text('$_error'),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (recommendation != null) ...<Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            recommendation.permissionLevel,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const Spacer(),
                          Text(
                            'confidence '
                            '${(recommendation.confidence * 100).round()}%',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(recommendation.summary),
                      if (recommendation.reasonCodes.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: <Widget>[
                            for (final code in recommendation.reasonCodes)
                              Chip(label: Text(code)),
                          ],
                        ),
                      ],
                      if (recommendation.candidateChanges.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        const Text(
                          'Proposed changes (require confirmation)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        for (final change in recommendation.candidateChanges)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.schedule_outlined),
                            title: Text(change.action),
                            subtitle: Text(
                              '${change.deltaMinutes} min · ${change.reason}',
                            ),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'Nothing was changed. Accept these changes in '
                          'the schedule screen after review.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('request-recommendation-button'),
              onPressed: _loading ? null : _request,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _recommendation == null
                    ? 'Request recommendation'
                    : 'Request another',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
