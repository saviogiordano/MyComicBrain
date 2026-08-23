import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/cover_analysis_provider_config.dart';

void main() {
  test(
    'senza --dart-define=COVER_ANALYSIS_PROVIDER il default resta claude',
    () {
      expect(CoverAnalysisProviderConfig.kind, CoverAnalysisProviderKind.claude);
    },
  );
}
