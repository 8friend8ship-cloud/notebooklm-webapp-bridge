# Managed extension platform scope

Current required publishing/control domains:
- Blogger: https://www.blogger.com/*
- YouTube Studio: https://studio.youtube.com/*
- Instagram: https://www.instagram.com/*
- TikTok: https://www.tiktok.com/*
- Naver Blog: https://blog.naver.com/*
- Naver Cafe: https://cafe.naver.com/*
- Naver Clip: https://clip.naver.com/*
- Pinterest: https://www.pinterest.com/*
- NotebookLM and Flow remain on their existing dedicated bridges.
- Deployed front-app domains are resolved from the central deployment registry and added as exact domains, never as `<all_urls>`.

Publisher bridge remains draft/no-publish until each platform passes login/editor detect + fill/readback/clear x2 and the first live-publication gate is approved.
