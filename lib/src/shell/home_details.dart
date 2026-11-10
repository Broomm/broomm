part of 'home_screen.dart';

typedef _HomeDetailsStyle = ({
  bool hasLead,
  double? logoGap,
  double actionWidth,
  bool importantNote,
});

class _HomeDetailsParentData extends ContainerBoxParentData<RenderBox> {}

class _HomeDetails extends MultiChildRenderObjectWidget {
  _HomeDetails({
    required Widget? lead,
    required Widget actions,
    required Widget? note,
    required double? logoGap,
    required double actionWidth,
    required bool importantNote,
  }) : style = (
         hasLead: lead != null,
         logoGap: logoGap,
         actionWidth: actionWidth,
         importantNote: importantNote,
       ),
       super(
         children: [if (lead != null) lead, actions, if (note != null) note],
       );

  final _HomeDetailsStyle style;

  @override
  _RenderHomeDetails createRenderObject(BuildContext context) =>
      _RenderHomeDetails(style);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHomeDetails renderObject,
  ) {
    renderObject.style = style;
  }
}

// The logo's height depends on its decoded aspect ratio and available width.
// Measure the stacked layout first, then reflow the same controls so resizing
// never replaces the focused button or requires a vertical scroll viewport.
class _RenderHomeDetails extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderHomeDetails(this._style);
  _HomeDetailsStyle _style;

  set style(_HomeDetailsStyle value) {
    if (value == _style) return;
    _style = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _HomeDetailsParentData();
    }
  }

  void _position(RenderBox child, double x, double y) {
    (child.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      x,
      y,
    );
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final width = size.width;
    final height = size.height;
    final lead = _style.hasLead ? firstChild : null;
    final actions = lead == null ? firstChild! : childAfter(lead)!;
    final note = childAfter(actions);
    const noteGap = 12.0, actionGap = 10.0;
    var reserved = 0.0;
    if (_style.importantNote && note != null) {
      note.layout(
        BoxConstraints(maxWidth: width, maxHeight: height * .3),
        parentUsesSize: true,
      );
      reserved = note.size.height + math.min(noteGap, height * .06);
    }
    final available = height - reserved;
    final actionWidth = math.min(_style.actionWidth, width);
    void layoutActions(double width) => actions.layout(
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: available),
      parentUsesSize: true,
    );

    layoutActions(actionWidth);
    lead?.layout(
      BoxConstraints(maxWidth: width, maxHeight: available),
      parentUsesSize: true,
    );
    final preferredGap = _style.logoGap ?? 8;
    final stackedHeight =
        (lead?.size.height ?? 0) + actionGap + actions.size.height;
    double bottom;
    if (_style.logoGap != null &&
        lead != null &&
        width >= 112 &&
        preferredGap + stackedHeight > available) {
      final horizontalGap = math.min(16.0, width * .08);
      final sideActionWidth = math.min(actionWidth, width * .62);
      layoutActions(sideActionWidth);
      lead.layout(
        BoxConstraints(
          maxWidth: width - sideActionWidth - horizontalGap,
          maxHeight: available,
        ),
        parentUsesSize: true,
      );
      final rowHeight = math.max(lead.size.height, actions.size.height);
      final top = math.min(preferredGap, available - rowHeight);
      bottom = top + rowHeight;
      _position(lead, 0, bottom - lead.size.height);
      _position(
        actions,
        lead.size.width + horizontalGap,
        bottom - actions.size.height,
      );
    } else {
      final remaining = available - actions.size.height;
      final between = math.min(actionGap, remaining);
      if (lead != null && lead.size.height > remaining - between) {
        lead.layout(
          BoxConstraints(maxWidth: width, maxHeight: remaining - between),
          parentUsesSize: true,
        );
      }
      final leadHeight = lead?.size.height ?? 0;
      final top = math.min(preferredGap, remaining - between - leadHeight);
      if (lead != null) _position(lead, 0, top);
      final actionTop = top + leadHeight + between;
      _position(actions, 0, actionTop);
      bottom = actionTop + actions.size.height;
    }
    if (note != null) {
      final gap = math.min(
        noteGap,
        _style.importantNote ? reserved - note.size.height : height - bottom,
      );
      final top = bottom + gap;
      if (!_style.importantNote) {
        note.layout(
          BoxConstraints(
            maxWidth: width,
            maxHeight: math.max(0.0, height - top),
          ),
          parentUsesSize: true,
        );
      }
      _position(note, 0, top);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
