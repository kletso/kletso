import 'package:kletso_core/kletso_core.dart';

import '../registry/registry.dart';
import 'chart_block.dart';
import 'content_blocks.dart';
import 'form_blocks.dart';
import 'layout_blocks.dart';
import 'media_blocks.dart';
import 'structure_blocks.dart';

/// The built-in builder for [type], or `null` when [type] is not a built-in.
KletsoComponentBuilder? kletsoBuiltinBuilder(String type) => switch (type) {
  KletsoBuiltinTypes.text => buildTextBlock,
  KletsoBuiltinTypes.markdown => buildMarkdownBlock,
  KletsoBuiltinTypes.card => buildCardBlock,
  KletsoBuiltinTypes.row => buildRowBlock,
  KletsoBuiltinTypes.column => buildColumnBlock,
  KletsoBuiltinTypes.divider => buildDividerBlock,
  KletsoBuiltinTypes.image => buildImageBlock,
  KletsoBuiltinTypes.avatar => buildAvatarBlock,
  KletsoBuiltinTypes.button => buildButtonBlock,
  KletsoBuiltinTypes.list => buildListBlock,
  KletsoBuiltinTypes.table => buildTableBlock,
  KletsoBuiltinTypes.chart => buildChartBlock,
  KletsoBuiltinTypes.carousel => buildCarouselBlock,
  KletsoBuiltinTypes.form => buildFormBlock,
  KletsoBuiltinTypes.input => buildInputBlock,
  KletsoBuiltinTypes.select => buildSelectBlock,
  KletsoBuiltinTypes.confirm => buildConfirmBlock,
  KletsoBuiltinTypes.loading => buildLoadingBlock,
  KletsoBuiltinTypes.error => buildErrorBlock,
  KletsoBuiltinTypes.badge => buildBadgeBlock,
  KletsoBuiltinTypes.link => buildLinkBlock,
  KletsoBuiltinTypes.map => buildMapBlock,
  KletsoBuiltinTypes.video => buildVideoBlock,
  KletsoBuiltinTypes.audio => buildAudioBlock,
  KletsoBuiltinTypes.rating => buildRatingBlock,
  KletsoBuiltinTypes.steps => buildStepsBlock,
  KletsoBuiltinTypes.accordion => buildAccordionBlock,
  KletsoBuiltinTypes.tabs => buildTabsBlock,
  KletsoBuiltinTypes.countdown => buildCountdownBlock,
  KletsoBuiltinTypes.progress => buildProgressBlock,
  _ => null,
};
