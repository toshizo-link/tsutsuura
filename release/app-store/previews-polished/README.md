# Generated preview concepts — not upload ready

These four draft PNGs were created with the built-in image_gen editing tool on 2026-09-05. The prompt set is in prompts.json. Source screenshots remain unchanged under ../screenshots/.

The angular Japanese headlines, cyan square frames, and dotted charcoal backdrop provide the requested matching visual direction. Header/subline Japanese reads correctly in all four.

Do not upload these draft images to App Store Connect:

- Output dimensions are 851×1849 (01,03,04) and 851×1848 (02), despite the explicit request for 1320×2868.
- The generator reconstructed inset UI pixels. In 02 the caution paragraph reflows versus the source screenshot; in 04 the screen is vertically compressed and the outer bottom edge touches the canvas. Original screenshot pixel/layout preservation is not guaranteed for any image.
- The generated backdrop includes slight tonal texture despite the requested flat colors.

A production composition should preserve the original screenshot rasters and use an exact-size, consistent heading/frame layout. No post-generation raster edits were performed.

