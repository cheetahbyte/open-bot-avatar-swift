# Changelog

## 0.3.0

- Track [Open Bot Avatar 0.3.0](https://github.com/DominikScholz/open-bot-avatar/tree/5e64c081971eb296f562544641bad37d40fb36b6).
- Align major and minor versions with upstream; native patch releases can have different patch numbers.
- Separate six activity states from neutral and happy moods, preserving state clocks through mood changes and interrupted transitions.
- Add morphing eyes, replacement marks, and gradient ribbons to frames, SVG output, and the native painter.
- Port smoother volume contours and refresh the catalog, including the egg avatar.
- Add upstream parity, geometry, animation, bounds, and Core Graphics rendering tests.

### Upgrade from 0.1.0

Custom renderers must handle ribbon shapes and filled eye paths; poses use numeric eye looks.
Legacy idle and thinking mood calls remain supported but are deprecated. Thinking now displays three dots instead of the body.
The avatar definition contract remains version 1.
