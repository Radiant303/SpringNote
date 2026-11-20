import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:graphview/GraphView.dart';

import '../../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'markdown_code_block.dart';
import 'spring_tree_parser.dart';

/// Radial mind map layout for springtree blocks.
///
/// graphview's stock [MindmapAlgorithm] is unusable for real labels: the
/// horizontal distance from the root is `depth * levelSeparation +
/// maxNodeHeight / 2` (node widths ignored, so longer labels overlap their
/// parents) and its vertical post-shift by `root.y / 2` breaks the spacing
/// between left- and right-side subtrees. This layout therefore computes
/// both axes itself:
///
/// - the root's children are split into left/right sides, balanced by leaf
///   count;
/// - x: each depth level starts at the previous level's outer edge plus
///   `levelSeparation`, using the widest measured node per side and depth;
/// - y: leaf slots are handed out top to bottom (`siblingSeparation` apart)
///   and every parent is centered on its children, which by construction
///   cannot overlap.
class _RadialMindmapAlgorithm extends Algorithm {
  _RadialMindmapAlgorithm(BuchheimWalkerConfiguration configuration)
    : _gap = configuration.levelSeparation.toDouble(),
      _siblingGap = configuration.siblingSeparation.toDouble() {
    // MindmapEdgeRenderer draws bezier edges and flips their direction for
    // the (negative-x) left side; only the orientation logic is reused.
    renderer = MindmapEdgeRenderer(configuration);
  }

  final double _gap;
  final double _siblingGap;

  final Map<Node, int> _depth = <Node, int>{};
  final Map<Node, int> _side = <Node, int>{};

  @override
  void init(Graph? graph) {}

  @override
  void setDimensions(double width, double height) {}

  @override
  Size run(Graph? graph, double shiftX, double shiftY) {
    final g = graph!;
    if (g.nodes.isEmpty) {
      return Size.zero;
    }
    _depth.clear();
    _side.clear();

    final root = g.nodes.firstWhere(
      (n) => g.predecessorsOf(n).isEmpty,
      orElse: () => g.nodes.first,
    );

    // Breadth-first depth assignment; unreachable nodes (defensive — the
    // parser always yields a single-rooted tree) are pinned to depth 1.
    _depth[root] = 0;
    final queue = <Node>[root];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      for (final child in g.successorsOf(node)) {
        _depth[child] = _depth[node]! + 1;
        queue.add(child);
      }
    }
    for (final node in g.nodes) {
      _depth[node] ??= 1;
    }

    // Split the root's children into sides, balanced by leaf count.
    int leafCount(Node node) {
      final children = g.successorsOf(node);
      if (children.isEmpty) {
        return 1;
      }
      var count = 0;
      for (final child in children) {
        count += leafCount(child);
      }
      return count;
    }

    void markSide(Node node, int side) {
      _side[node] = side;
      for (final child in g.successorsOf(node)) {
        markSide(child, side);
      }
    }

    var leftLeaves = 0;
    var rightLeaves = 0;
    final leftRoots = <Node>[];
    final rightRoots = <Node>[];
    for (final child in g.successorsOf(root)) {
      final leaves = leafCount(child);
      if (leftLeaves <= rightLeaves) {
        leftRoots.add(child);
        leftLeaves += leaves;
        markSide(child, -1);
      } else {
        rightRoots.add(child);
        rightLeaves += leaves;
        markSide(child, 1);
      }
    }
    for (final node in g.nodes) {
      _side[node] ??= 1;
    }

    // X: per side and depth, offset by the widest node of the level before.
    final maxWidth = <int, Map<int, double>>{
      -1: <int, double>{},
      1: <int, double>{},
    };
    for (final node in g.nodes) {
      final depth = _depth[node]!;
      if (depth == 0) {
        continue;
      }
      final widths = maxWidth[_side[node]]!;
      widths[depth] = math.max(widths[depth] ?? 0, node.width);
    }
    final xBySideAndDepth = <int, Map<int, double>>{
      -1: <int, double>{},
      1: <int, double>{},
    };
    for (final side in const <int>[-1, 1]) {
      final widths = maxWidth[side]!;
      if (widths.isEmpty) {
        continue;
      }
      var cursor = side == 1 ? root.width : 0.0;
      for (var d = 1; d <= widths.keys.reduce(math.max); d++) {
        final width = widths[d] ?? 0;
        if (side == 1) {
          cursor += _gap;
          xBySideAndDepth[side]![d] = cursor;
          cursor += width;
        } else {
          cursor -= _gap + width;
          xBySideAndDepth[side]![d] = cursor;
        }
      }
    }

    // Y: contiguous leaf slots, parents centered on their children. Every
    // subtree returns its vertical center; the shared cursor guarantees the
    // next subtree starts below everything this one occupies.
    double layoutSide(Iterable<Node> roots) {
      var cursor = 0.0;

      double place(Node node) {
        final children = g.successorsOf(node);
        if (children.isEmpty) {
          node.y = cursor;
          cursor += node.height + _siblingGap;
          return node.y + node.height / 2;
        }
        final firstCenter = place(children.first);
        var lastCenter = firstCenter;
        for (final child in children.skip(1)) {
          lastCenter = place(child);
        }
        final center = (firstCenter + lastCenter) / 2;
        node.y = center - node.height / 2;
        final bottom = node.y + node.height + _siblingGap;
        if (cursor < bottom) {
          cursor = bottom;
        }
        return center;
      }

      for (final subtreeRoot in roots) {
        place(subtreeRoot);
      }
      return cursor;
    }

    final leftExtent = layoutSide(leftRoots);
    final rightExtent = layoutSide(rightRoots);
    final totalExtent = math.max(leftExtent, rightExtent);

    // Center both sides and the root on the same vertical band.
    void shiftSide(int side, double offset) {
      if (offset == 0) {
        return;
      }
      for (final node in g.nodes) {
        if (_side[node] == side) {
          node.y += offset;
        }
      }
    }

    shiftSide(-1, (totalExtent - leftExtent) / 2);
    shiftSide(1, (totalExtent - rightExtent) / 2);

    root.x = 0;
    root.y = totalExtent / 2 - root.height / 2;
    for (final node in g.nodes) {
      final depth = _depth[node]!;
      if (depth != 0) {
        node.x = xBySideAndDepth[_side[node]]![depth]!;
      }
      node.position = Offset(node.x + shiftX, node.y + shiftY);
    }

    return g.calculateGraphSize();
  }
}

/// Shared `codeBuilder` for every `GptMarkdown` instance in the app.
///
/// Routes ```springtree fences to the [SpringTreeBlock] mind map and keeps
/// every other language on the regular highlighted code block. Pass
/// `inlineNodeLimit: null` where the inline node cap should not apply
/// (the memoir page).
Widget buildSpringCodeBlock(
  BuildContext context,
  String name,
  String code,
  bool closed, {
  int? inlineNodeLimit = SpringTreeBlock.defaultInlineNodeLimit,
}) {
  if (name.trim().toLowerCase() == 'springtree') {
    return SpringTreeBlock(
      source: code,
      isComplete: closed,
      inlineNodeLimit: inlineNodeLimit,
    );
  }
  return MarkdownCodeBlock(language: name, code: code);
}

/// Renders a ```springtree code block as a mind map.
///
/// The block body is re-parsed on every rebuild (a single O(n) pass, see
/// [parseSpringTree]) and the resulting graph is diffed by stable node ids,
/// so while AI text streams in, existing nodes keep their state and only new
/// nodes play the grow animation — giving a progressive growth effect with
/// effectively zero parsing overhead.
class SpringTreeBlock extends StatefulWidget {
  const SpringTreeBlock({
    super.key,
    required this.source,
    this.isComplete = true,
    this.expand = false,
    this.inlineNodeLimit = defaultInlineNodeLimit,
  });

  /// Default for [inlineNodeLimit].
  static const int defaultInlineNodeLimit = 120;

  /// Raw body of the code fence (the indented list).
  final String source;

  /// Whether the closing fence has been received yet (streaming).
  final bool isComplete;

  /// Fill all the height the parent offers (fullscreen dialog) instead of
  /// sizing the canvas from the leaf count.
  final bool expand;

  /// Max nodes the inline (non-fullscreen) map mounts. Mounting node
  /// widgets is the dominant cost of rendering a large tree, so the inline
  /// block mounts only the first [inlineNodeLimit] nodes (breadth-first,
  /// so every mounted node's parent is mounted too) and reports the rest
  /// in the header. Null means no limit — for the memoir page, a single
  /// scrollable page where note-switch performance does not apply. The
  /// fullscreen dialog (`expand: true`) always mounts everything.
  final int? inlineNodeLimit;

  @override
  State<SpringTreeBlock> createState() => _SpringTreeBlockState();
}

class _SpringTreeBlockState extends State<SpringTreeBlock> {
  static const String _virtualRootId = '__springtree_root__';

  /// Depth colors for non-root nodes, chosen to read well on both themes.
  static const List<Color> _depthColors = <Color>[
    Color(0xFF3B82F6), // blue
    Color(0xFF22A06B), // green
    Color(0xFFE8890C), // orange
    Color(0xFF9B6DD7), // purple
    Color(0xFF14B8A6), // teal
    Color(0xFFE0639B), // pink
  ];

  /// The one and only graph instance, mutated in place by [_rebuildGraph].
  ///
  /// graphview diffs children by node identity: handing it a brand-new
  /// [Graph] per parse makes reused nodes keep stale scene positions (the
  /// render object maps old node instances to render boxes and copies
  /// offsets from the old instances). Stable instances keep everything
  /// consistent and let genuinely new nodes mount — and play the grow
  /// animation — on their own.
  final Graph _graph = Graph()..isTree = true;
  late SpringTree _tree;
  final Map<String, Node> _nodes = <String, Node>{};
  Map<String, SpringTreeNode> _items = <String, SpringTreeNode>{};
  bool _copied = false;

  /// View transform for the graph canvas, recreated whenever the graph
  /// branch remounts after a fallback.
  ///
  /// graphview 1.5.1's GraphView disposes even an externally provided
  /// TransformationController in its own dispose, so ownership follows the
  /// widget tree: while the graph branch is mounted the controller belongs
  /// to GraphView; while the fallback code block is shown (unparseable
  /// source) it belongs to this state. [_graphBranchMounted] and
  /// [_transformDisposedByGraphView] track that transfer so the controller
  /// is recreated after a GraphView unmount and disposed exactly once.
  late TransformationController _viewTransform;
  late GraphViewController _graphController;

  /// Whether the last build mounted a GraphView (which then owns
  /// [_viewTransform] and disposes it on unmount).
  bool _graphBranchMounted = false;

  /// Whether a previously mounted GraphView already disposed
  /// [_viewTransform]; the next graph build must recreate it first, and
  /// [dispose] must not dispose it again.
  bool _transformDisposedByGraphView = false;

  /// Above this many nodes added by a single graph rebuild, that whole batch
  /// skips the grow animation. The animation exists so nodes arriving one by
  /// one during streaming "grow" in; when a rebuild mounts dozens of nodes at
  /// once (first mount, or switching to a note whose tree differs
  /// structurally) it instead runs that many simultaneous opacity/scale
  /// animations — several expensive frames of widget rebuilds and
  /// save-layers, i.e. visible switch lag.
  static const int _maxAnimatedInitialNodes = 96;

  /// How many nodes the inline cap currently hides (always 0 when
  /// [SpringTreeBlock.expand] is true or the limit was lifted).
  int _hiddenNodeCount = 0;

  /// Ids that must render without the grow animation: every batch a single
  /// [_rebuildGraph] added above [_maxAnimatedInitialNodes]. Pruned to live
  /// nodes on every rebuild, so a node removed and later re-added by a small
  /// streaming diff animates again.
  final Set<String> _staticRenderIds = <String>{};

  /// Size of the graph canvas, tracked from [LayoutBuilder] constraints.
  Size _viewportSize = Size.zero;
  bool _userInteractedWithView = false;
  bool _applyingFit = false;

  /// True while the graph stays hidden until the initial fit transform has
  /// been applied (first frame after a mount); prevents a one-frame flash
  /// of the unfitted identity-transform graph.
  bool _awaitingInitialFit = true;

  final Algorithm _algorithm = _RadialMindmapAlgorithm(
    BuchheimWalkerConfiguration(
      siblingSeparation: 18,
      levelSeparation: 56,
      subtreeSeparation: 28,
      orientation: BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT,
    ),
  );

  @override
  void initState() {
    super.initState();
    _createViewTransform();
    _rebuildGraph();
  }

  /// Creates the view transform and the graphview controller wrapping it,
  /// and attaches the user-interaction listener. Called from [initState]
  /// and again whenever the graph branch remounts after a fallback, because
  /// the unmounted GraphView disposed the previous controller.
  void _createViewTransform() {
    _viewTransform = TransformationController();
    _graphController = GraphViewController(
      transformationController: _viewTransform,
    );
    // Any transform change that did not come from _fitGraphIntoView is the
    // user panning/zooming; afterwards the view is left alone.
    _viewTransform.addListener(() {
      if (!_applyingFit) {
        _userInteractedWithView = true;
      }
    });
  }

  @override
  void didUpdateWidget(SpringTreeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _rebuildGraph();
    }
  }

  @override
  void dispose() {
    for (final pointer in _panPointers) {
      GestureBinding.instance.pointerRouter.removeRoute(
        pointer,
        _routeMousePan,
      );
    }
    _panPointers.clear();
    // Dispose the transform only while this state still owns it: a mounted
    // GraphView disposes it during unmount, and an already unmounted one
    // left it disposed.
    if (!_graphBranchMounted && !_transformDisposedByGraphView) {
      _viewTransform.dispose();
    }
    super.dispose();
  }

  /// Centers the whole graph in the viewport and schedules it after the
  /// frame in which node sizes have been measured. Small trees stay at 100%
  /// zoom; large trees are shrunk to fit — the initial view always shows the
  /// full map, and the user can zoom in (wheel, buttons) or open fullscreen
  /// for readability. Skipped once the user takes over the canvas.
  void _scheduleFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // _transformDisposedByGraphView: the callback may outlive the graph
      // branch that scheduled it; its controller is dead by then.
      if (!mounted || _transformDisposedByGraphView) {
        return;
      }
      if (!_userInteractedWithView) {
        final bounds = _graph.calculateGraphBounds();
        if (!bounds.isEmpty && !_viewportSize.isEmpty) {
          const padding = 28.0;
          final fitScale = math.min(
            (_viewportSize.width - padding * 2) / bounds.width,
            (_viewportSize.height - padding * 2) / bounds.height,
          );
          final scale = math.min(1.0, fitScale);
          final dx =
              (_viewportSize.width - bounds.width * scale) / 2 -
              bounds.left * scale;
          final dy =
              (_viewportSize.height - bounds.height * scale) / 2 -
              bounds.top * scale;
          _applyingFit = true;
          _viewTransform.value = Matrix4.identity()
            ..translateByDouble(dx, dy, 0, 1)
            ..scaleByDouble(scale, scale, 1, 1);
          _applyingFit = false;
        }
      }
      // Reveal the graph whether or not a fit was applied this frame;
      // otherwise an early return above would keep it hidden forever.
      if (_awaitingInitialFit) {
        setState(() => _awaitingInitialFit = false);
      }
    });
  }

  /// Current 2D zoom factor. `getMaxScaleOnAxis` is unusable for this: it
  /// also inspects the (always 1x) Z basis, so it never reports less than 1.
  double _currentScale() {
    final s = _viewTransform.value.storage;
    return math.sqrt(s[0] * s[0] + s[1] * s[1]);
  }

  /// Multiplies the current zoom by [factor] around the viewport center.
  /// Counts as user interaction, so automatic fitting stops.
  void _zoomBy(double factor) {
    final current = _currentScale();
    final nextScale = (current * factor).clamp(0.2, 3.0);
    if (nextScale == current) {
      return;
    }
    final applied = nextScale / current;
    final cx = _viewportSize.width / 2;
    final cy = _viewportSize.height / 2;
    _viewTransform.value = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(applied, applied, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1)
      ..multiply(_viewTransform.value);
  }

  /// Re-enables automatic fitting (undoes user pan/zoom) and refits.
  void _fitAndFollow() {
    _userInteractedWithView = false;
    _scheduleFit();
  }

  /// Claims mouse-wheel events in the pointer signal resolver so an outer
  /// [Scrollable] never scrolls the page while the user zooms the graph.
  ///
  /// Flutter dispatches pointer signals to every [Listener] in the hit path:
  /// graphview's InteractiveViewer zooms on the event but never claims it,
  /// so without this the outer scroll view would scroll too. This Listener
  /// sits deeper in the hit path, so its registration wins and the outer
  /// Scrollable's scroll callback is dropped.
  void _claimWheelEvent(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
    }
  }

  /// Mouse pointers currently being panned by [_routeMousePan].
  final Set<int> _panPointers = <int>{};

  /// Starts tracking a mouse drag on the canvas. Move/up events are routed
  /// through the pointer router, so panning keeps working even when the
  /// cursor leaves the block mid-drag.
  void _trackMousePan(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryButton) {
      return;
    }
    if (_panPointers.add(event.pointer)) {
      GestureBinding.instance.pointerRouter.addRoute(
        event.pointer,
        _routeMousePan,
      );
    }
  }

  void _routeMousePan(PointerEvent event) {
    if (event is PointerMoveEvent && (event.buttons & kPrimaryButton) != 0) {
      _panBy(event.delta);
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      GestureBinding.instance.pointerRouter.removeRoute(
        event.pointer,
        _routeMousePan,
      );
      _panPointers.remove(event.pointer);
    }
  }

  /// Pans the view by a drag delta (in viewport pixels).
  void _panBy(Offset delta) {
    _viewTransform.value = Matrix4.identity()
      ..translateByDouble(delta.dx, delta.dy, 0, 1)
      ..multiply(_viewTransform.value);
  }

  /// Claims mouse drags on the canvas with an eager recognizer; the actual
  /// panning is driven by [_routeMousePan].
  ///
  /// InteractiveViewer pans through a ScaleGestureRecognizer, which loses
  /// the gesture arena unpredictably to the TapAndPanGestureRecognizer that
  /// an enclosing SelectionArea installs for mouse selection (chat messages,
  /// previews): that recognizer wins by deadline timer whenever a drag
  /// hesitates past its slop, so the mouse moves but the graph does not.
  /// The eager recognizer accepts the pointer at mouse-down — deepest in the
  /// hit path, before the selection recognizer even joins the arena — so
  /// canvas drags always pan. Touch keeps InteractiveViewer's own pan; wheel
  /// zoom and trackpad pinch are pointer signals and stay unaffected.
  Widget _buildPanClaimer({required Widget child}) {
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              () => EagerGestureRecognizer(
                supportedDevices: <PointerDeviceKind>{PointerDeviceKind.mouse},
              ),
              (recognizer) {},
            ),
      },
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }

  void _openFullscreen() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: AppTheme.colors(dialogContext).background,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SpringTreeBlock(
            source: widget.source,
            isComplete: widget.isComplete,
            expand: true,
          ),
        ),
      ),
    );
  }

  void _rebuildGraph() {
    final tree = parseSpringTree(widget.source);
    // Breadth-first collection, so every collected node's parent is
    // collected as well and edges stay valid. The inline cap stops
    // collecting at [SpringTreeBlock.inlineNodeLimit] while the walk
    // continues, just for the total count shown in the header.
    final wanted = <String, SpringTreeNode>{};
    final limit = widget.inlineNodeLimit;
    final cap = widget.expand || limit == null ? 1 << 30 : limit;
    var totalNodes = 0;
    final queue = ListQueue<SpringTreeNode>.from(tree.roots);
    while (queue.isNotEmpty) {
      final item = queue.removeFirst();
      totalNodes++;
      if (wanted.length < cap) {
        wanted[item.id] = item;
      }
      queue.addAll(item.children);
    }
    final useVirtualRoot = tree.roots.length > 1;

    // Remove vanished nodes, deepest first so Graph.removeNode's recursive
    // subtree removal finds nothing left to cascade into.
    final removedIds =
        _nodes.keys
            .where((id) => id != _virtualRootId && !wanted.containsKey(id))
            .toList()
          ..sort(
            (a, b) =>
                '.'.allMatches(b).length.compareTo('.'.allMatches(a).length),
          );
    for (final id in removedIds) {
      _graph.removeNode(_nodes.remove(id));
    }
    if (!useVirtualRoot && _nodes.containsKey(_virtualRootId)) {
      _graph.removeNode(_nodes.remove(_virtualRootId));
    }

    // Add new nodes and edges. A node's parent is encoded in its path id, so
    // edges never need rewiring — only label text changes in place, which is
    // picked up from _items when the node widget rebuilds.
    final addedIds = <String>[];
    void ensure(SpringTreeNode item, Node? parent) {
      // Cut away by the inline cap: breadth-first collection means no
      // descendant of an unwanted node is wanted either, so the whole
      // subtree can be skipped.
      if (!wanted.containsKey(item.id)) {
        return;
      }
      final node = _nodes.putIfAbsent(item.id, () {
        final created = Node.Id(item.id);
        _graph.addNode(created);
        addedIds.add(item.id);
        return created;
      });
      if (parent != null) {
        _graph.addEdge(parent, node);
      }
      for (final child in item.children) {
        ensure(child, node);
      }
    }

    if (tree.roots.length == 1) {
      ensure(tree.roots.single, null);
    } else if (useVirtualRoot) {
      // Multiple top-level lines: join them under a small origin dot so the
      // tree layout still has a single root.
      final origin = _nodes.putIfAbsent(_virtualRootId, () {
        final created = Node.Id(_virtualRootId);
        _graph.addNode(created);
        return created;
      });
      for (final root in tree.roots) {
        ensure(root, origin);
      }
    }

    // A wholesale swap (first mount, note switch to a different tree) renders
    // its batch statically; small streaming diffs keep the grow animation.
    if (addedIds.length > _maxAnimatedInitialNodes) {
      _staticRenderIds.addAll(addedIds);
    }
    _staticRenderIds.removeWhere((id) => !wanted.containsKey(id));

    setState(() {
      _tree = tree;
      _items = wanted;
      _hiddenNodeCount = totalNodes - wanted.length;
    });
    _scheduleFit();
  }

  Future<void> _copySource() async {
    await Clipboard.setData(ClipboardData(text: widget.source));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tree.isEmpty) {
      // Nothing parseable (yet) — behave like an ordinary code block. The
      // GraphView replaced by this build disposes the transform it owns.
      if (_graphBranchMounted) {
        _graphBranchMounted = false;
        _transformDisposedByGraphView = true;
      }
      return MarkdownCodeBlock(language: 'springtree', code: widget.source);
    }
    if (_transformDisposedByGraphView) {
      // Reviving the graph branch after a fallback: the previous transform
      // is dead, so start over with a fresh, unfitted view.
      _createViewTransform();
      _transformDisposedByGraphView = false;
      _userInteractedWithView = false;
      _awaitingInitialFit = true;
    }
    _graphBranchMounted = true;

    final colors = AppTheme.colors(context);

    final graphArea = LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              // Hidden until the initial fit transform has been applied, so
              // the first frame never shows the unfitted identity view.
              child: Opacity(
                opacity: _awaitingInitialFit ? 0 : 1,
                // Isolate graph repaints (animations, pan/zoom) from the
                // surrounding markdown content.
                child: RepaintBoundary(
                  child: Listener(
                    onPointerSignal: _claimWheelEvent,
                    onPointerDown: _trackMousePan,
                    child: _buildPanClaimer(
                      child: GraphView.builder(
                        // One persistent graph, synced in place; the element
                        // tree diffs node widgets by their stable ValueKeys,
                        // so only new nodes animate.
                        graph: _graph,
                        algorithm: _algorithm,
                        controller: _graphController,
                        // Keep position animation off: graphview restarts a
                        // 600ms position lerp on every graph rebuild, so
                        // during streaming/typing it never converges and
                        // nodes overlap. New nodes still get a grow
                        // animation from _buildNode.
                        animated: false,
                        // centerGraph must stay off: graphview implements it
                        // by laying the graph out around (100000, 100000),
                        // far outside the initial viewport, so the block
                        // would render blank.
                        centerGraph: false,
                        paint: Paint()
                          ..color = colors.border
                          ..strokeWidth = 1.4
                          ..style = PaintingStyle.stroke,
                        builder: _buildNode,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(right: 8, bottom: 8, child: _buildZoomControls(colors)),
          ],
        );
      },
    );

    // The mind map is a canvas, not text: keep an enclosing SelectionArea
    // (chat messages, previews) from making node labels selectable —
    // selecting text would also swallow the canvas pan gesture.
    return SelectionContainer.disabled(
      child: Container(
        margin: widget.expand
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(colors),
            if (widget.expand)
              Expanded(child: graphArea)
            else
              SizedBox(
                height: math.min(
                  520.0,
                  math.max(200.0, _tree.leafCount * 42.0 + 64.0),
                ),
                child: graphArea,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SpringThemeColors colors) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: AppTheme.continuousBoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree_outlined, size: 13, color: colors.textSubtle),
          const SizedBox(width: 6),
          Text(
            'springtree',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          if (!widget.isComplete) ...[
            const SizedBox(width: 8),
            Text(
              l10n(context).coreTreeGenerating,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSubtle,
                fontSize: 10,
                height: 1,
              ),
            ),
          ],
          if (_hiddenNodeCount > 0) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: l10n(context).coreTreeInlineLimitHint(
                _hiddenNodeCount,
                widget.inlineNodeLimit ?? 0,
              ),
              child: Text(
                '+$_hiddenNodeCount',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSubtle,
                  fontSize: 10,
                  height: 1,
                ),
              ),
            ),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: _copySource,
            style: TextButton.styleFrom(
              foregroundColor: colors.textSubtle,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            icon: Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 13,
            ),
            label: Text(
              _copied
                  ? l10n(context).coreCodeCopied
                  : l10n(context).coreCodeCopy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControls(SpringThemeColors colors) {
    Widget button(IconData icon, String tooltip, VoidCallback onPressed) {
      return IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 15),
        color: colors.textSubtle,
        splashRadius: 14,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
      );
    }

    return Container(
      decoration: AppTheme.continuousBoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.expand) ...[
            // The fullscreen dialog gets a real exit affordance instead of
            // relying on the ESC shortcut alone.
            button(
              Icons.fullscreen_exit_rounded,
              l10n(context).coreTreeExitFullscreen,
              () => Navigator.of(context).maybePop(),
            ),
            Divider(height: 1, thickness: 1, color: colors.divider),
          ] else ...[
            button(
              Icons.fullscreen_rounded,
              l10n(context).coreTreeFullscreen,
              _openFullscreen,
            ),
            Divider(height: 1, thickness: 1, color: colors.divider),
          ],
          button(
            Icons.add_rounded,
            l10n(context).coreTreeZoomIn,
            () => _zoomBy(1.25),
          ),
          Divider(height: 1, thickness: 1, color: colors.divider),
          button(
            Icons.remove_rounded,
            l10n(context).coreTreeZoomOut,
            () => _zoomBy(0.8),
          ),
          Divider(height: 1, thickness: 1, color: colors.divider),
          button(
            Icons.fit_screen_rounded,
            l10n(context).coreTreeFitAll,
            _fitAndFollow,
          ),
        ],
      ),
    );
  }

  Widget _buildNode(Node node) {
    final id = node.key!.value;
    if (id == _virtualRootId) {
      final colors = AppTheme.colors(context);
      return Container(
        key: const ValueKey(_virtualRootId),
        width: 10,
        height: 10,
        decoration: AppTheme.continuousBoxDecoration(
          color: colors.textSubtle,
          shape: BoxShape.circle,
        ),
      );
    }
    final item = _items[id]!;
    // The ValueKey lets GraphView reuse this widget's element across graph
    // rebuilds, so the grow animation only runs for genuinely new nodes.
    if (_staticRenderIds.contains(id)) {
      // Mounted as part of a large batch (first mount, note switch): render
      // statically instead of animating dozens of nodes at once.
      return KeyedSubtree(
        key: ValueKey('springtree_$id'),
        child: _buildNodeCard(item),
      );
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey('springtree_$id'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
        );
      },
      child: _buildNodeCard(item),
    );
  }

  Widget _buildNodeCard(SpringTreeNode item) {
    final colors = AppTheme.colors(context);
    final isRoot = item.depth == 0 && _tree.roots.length == 1;
    final depthColor = _depthColors[(item.depth - 1) % _depthColors.length];

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: AppTheme.continuousBoxDecoration(
        color: isRoot ? colors.text : colors.surface,
        borderRadius: BorderRadius.circular(isRoot ? 18 : 10),
        border: Border.all(
          color: isRoot ? colors.text : depthColor,
          width: isRoot ? 1 : 1.4,
        ),
        // No boxShadow: every graph repaint (note switches, streaming
        // growth) redraws all nodes inside one RepaintBoundary, and a
        // blurred shadow per node costs 10-40ms of raster on large trees.
      ),
      child: Text(
        item.label,
        style: TextStyle(
          fontSize: isRoot ? 13 : 12.5,
          height: 1.35,
          fontWeight: isRoot ? FontWeight.w600 : FontWeight.w500,
          color: isRoot ? colors.surface : colors.text,
        ),
      ),
    );
  }
}
