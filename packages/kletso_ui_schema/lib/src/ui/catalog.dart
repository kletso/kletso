/// Names of the component types every conforming renderer ships.
///
/// Custom types are namespaced (`acme.productCard`) and declared per project;
/// anything not in this set and not registered by the host renders the
/// surface's `fallbackText`.
abstract final class KletsoBuiltinTypes {
  /// Plain text, no markdown.
  static const String text = 'text';

  /// Markdown, links only.
  static const String markdown = 'markdown';

  /// Padded container with optional title and subtitle.
  static const String card = 'card';

  /// Horizontal layout.
  static const String row = 'row';

  /// Vertical layout.
  static const String column = 'column';

  /// Horizontal rule.
  static const String divider = 'divider';

  /// Remote image from an allowlisted host.
  static const String image = 'image';

  /// Small round image or initials.
  static const String avatar = 'avatar';

  /// Button; must carry at least one action.
  static const String button = 'button';

  /// Vertical list of items.
  static const String list = 'list';

  /// Data table, at most 50 rows.
  static const String table = 'table';

  /// Line, bar or pie chart rendered natively.
  static const String chart = 'chart';

  /// Horizontal scroller of cards.
  static const String carousel = 'carousel';

  /// Multi-field form submitted as one structured value.
  static const String form = 'form';

  /// Single-field prompt.
  static const String input = 'input';

  /// Single or multi select.
  static const String select = 'select';

  /// Runtime-emitted approval block for a paused tool call.
  static const String confirm = 'confirm';

  /// Runtime-emitted progress block while tools run.
  static const String loading = 'loading';

  /// Error block.
  static const String error = 'error';

  /// Small status label.
  static const String badge = 'badge';

  /// Text link to an allowlisted URL.
  static const String link = 'link';

  /// Map with markers; hosts may render a live map, the SDK paints a static one.
  static const String map = 'map';

  /// Video with poster; hosts may render a player, the SDK opens the URL.
  static const String video = 'video';

  /// Audio clip; hosts may render a player, the SDK opens the URL.
  static const String audio = 'audio';

  /// Star rating, read-only or interactive.
  static const String rating = 'rating';

  /// Ordered steps with a status each (order tracking, onboarding).
  static const String steps = 'steps';

  /// Expandable sections.
  static const String accordion = 'accordion';

  /// Tabbed children.
  static const String tabs = 'tabs';

  /// Live countdown to a timestamp.
  static const String countdown = 'countdown';

  /// Determinate progress bar.
  static const String progress = 'progress';

  /// Every built-in type name.
  static const Set<String> all = <String>{
    text,
    markdown,
    card,
    row,
    column,
    divider,
    image,
    avatar,
    button,
    list,
    table,
    chart,
    carousel,
    form,
    input,
    select,
    confirm,
    loading,
    error,
    badge,
    link,
    map,
    video,
    audio,
    rating,
    steps,
    accordion,
    tabs,
    countdown,
    progress,
  };

  /// Types whose `props.children` is a list of component ids.
  static const Set<String> containers = <String>{
    card,
    row,
    column,
    carousel,
    tabs,
    accordion,
  };

  /// Returns `true` when [type] is a built-in.
  static bool isBuiltin(String type) => all.contains(type);
}
