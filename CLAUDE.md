Engineering Notes

1. Always prefer performance as number 1 priority!
2. We are using Zig 0.15.2. make sure to use latest API's
   e.g. Check how we do ArrayList inits.

Each glyph carries its own clip bounds, and the fragment shader discards pixels outside. No extra draw calls, no scissor rect state changes, just a simple `discard_fragment()` in the shader.

## Glyph Ink Bounds Detection

When rasterizing glyphs with CoreText, the actual ink (visible pixels) may not
start exactly where we allocate padding. CoreText's anti-aliasing produces
variable padding depending on glyph shape:

| Glyph | Expected padding | Actual ink row |
| ----- | ---------------- | -------------- |
| 'A'   | 2                | 1              |
| 'o'   | 2                | 2              |
| 'u'   | 2                | 1              |

If we assume fixed padding, glyphs with different actual padding will be
vertically misaligned (e.g., 'u' appears lower than 'o' in "About").

**Solution**: After `CTFontDrawGlyphs`, scan the bitmap to find where ink
actually starts, then use that to compute `offset_x` and `offset_y`.

This matches how GPUI handles it - they use font-kit's `raster_bounds()` to
get exact pixel bounds before rendering. Our approach is equivalent but done
post-render via bitmap scanning.

**Performance**: The scan is O(width × height) but only runs once per glyph
since results are cached. For a typical 20×25 glyph, this is ~500 byte
comparisons - negligible compared to the CoreText rendering cost.

**References**:

- GPUI: `crates/gpui/src/platform/mac/text_system.rs` (raster_bounds + rasterize_glyph)
- Our implementation: `src/text/backends/coretext/face.zig` (renderGlyphSubpixel)

When creating apps/examples:
You can't nest `cx.box()` calls directly inside tuples\** because they return `void`. Use component structs (like `Card{}`, `CounterRow{}`) for nesting. The component's `render` method receives a `*Builder`and can call`b.box()` etc.

So we have a foundation for:

1. **Scroll containers** - push clip to viewport, render children, pop
2. **`overflow: hidden`** on any element - same pattern
3. **Nested clips** - the stack automatically intersects them
4. **Tooltips/dropdowns** that can overflow their parent - just don't push a clip

Design Philosophy

1. **Plain structs by default** - no wrappers needed for simple state
2. **Context when you need it** - opt-in to reactivity
3. **Components are just structs with `render`** - like GPUI Views
4. **Progressive complexity** - start simple, add power as needed
