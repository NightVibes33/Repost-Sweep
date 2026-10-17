# Third-party notices

Repost Sweep reuses removal logic from the projects below. Each MIT license is included in full because the app contains a substantial portion of that project’s approach.

## gabireze/tiktok-all-reposted-videos-remover

Used for the unrepost request and the verification flow: `POST /tiktok/v1/upvote/delete` with `aid=1988` and `item_id` on the query, an empty body, `tt-csrf-token` from `webapp.app-context`, and a follow-up read of `/api/repost/item_list/` that only counts a removal when the id is gone.

https://github.com/gabireze/tiktok-all-reposted-videos-remover

```
MIT License

Copyright (c) 2024 Gabriel de Rezende Gonçalves

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## BrittAbdula/tiktokrepostremover (ClearTok)

Used for the video-page share and repost-tab selectors. A control is tapped only when its `data-e2e` contains `remove-repost` or `aria-pressed` is true. Fill and color are not used.

https://github.com/BrittAbdula/tiktokrepostremover

```
MIT License

Copyright (c) 2026 BrittAbdula

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## kien234/tiktok-unrepost

No license is declared, and the repository ships a bundled webmssdk script. None of its source is copied. Repost Sweep does not replay a captured signed URL. Removal sends one plain `aid` and `item_id` POST with the page csrf token.
