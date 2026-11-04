import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    for (final name in ['scrolling_timeline', 'typing_timeline']) {
      final value = data[name];
      if (value is Map<String, dynamic>) {
        final summary = TimelineSummary.summarize(Timeline.fromJson(value));
        await Directory('build/performance').create(recursive: true);
        await File('build/performance/${name}_summary.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(summary.summaryJson),
        );
        await summary.writeTimelineToFile(
          name,
          destinationDirectory: 'build/performance',
          pretty: true,
        );
      }
    }
  },
);
