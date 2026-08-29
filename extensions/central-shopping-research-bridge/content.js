(() => {
  const MAX_SCROLLS = 16;
  const MAX_REVIEWS = 100;
  const MAX_SNIPPET = 360;
  const WAIT_MS = 650;

  const PLATFORM = (() => {
    const host = location.hostname.toLowerCase();
    if (host.includes('coupang.com')) return 'COUPANG';
    if (host.includes('aliexpress.com')) return 'ALIEXPRESS';
    if (host.includes('amazon.com')) return 'AMAZON';
    return 'UNKNOWN';
  })();

  const CONFIG = {
    COUPANG: {
      title: ['h1', '.prod-buy-header__title', '[class*="product-title"]'],
      price: ['.total-price', '.prod-sale-price', '[class*="price"]'],
      delivery: ['.prod-delivery-return-policy-table', '[class*="delivery"]', '[class*="shipping"]'],
      review: ['.sdp-review__article__list__review__content', '[class*="review__content"]', '[class*="review-content"]'],
      reviewAnchor: ['#btfTab', '[class*="review"]']
    },
    ALIEXPRESS: {
      title: ['h1', '[data-pl="product-title"]', '[class*="title--"]'],
      price: ['[data-pl="product-price"]', '[class*="price--"]', '[class*="price"]'],
      delivery: ['[class*="delivery"]', '[class*="shipping"]'],
      review: ['[class*="feedback-item"] [class*="content"]', '[class*="review"] [class*="content"]', '[class*="feedback"] p'],
      reviewAnchor: ['[class*="feedback"]', '[class*="review"]']
    },
    AMAZON: {
      title: ['#productTitle', 'h1'],
      price: ['.a-price .a-offscreen', '#priceblock_ourprice', '#priceblock_dealprice'],
      delivery: ['#deliveryBlockMessage', '#mir-layout-DELIVERY_BLOCK', '[data-csa-c-content-id*="delivery"]'],
      review: ['[data-hook="review-body"] span', '[data-hook="review-body"]'],
      reviewAnchor: ['#customerReviews', '[data-hook="reviews-medley-footer"]']
    }
  };

  const CLUSTERS = {
    value: ['가성비', '가격', '저렴', '비싸', 'value', 'price', 'worth'],
    quality: ['품질', 'quality', '튼튼', '불량', 'durable', 'broken'],
    taste: ['맛', '향', '고소', 'taste', 'flavor'],
    freshness: ['신선', '유통기한', '상함', 'fresh', 'expiry', 'expired'],
    packaging: ['포장', '파손', '누수', 'packaging', 'damaged', 'leak'],
    delivery: ['배송', '도착', 'delivery', 'shipping', 'arrived'],
    usability: ['사용', '요리', '설치', 'recipe', 'cook', 'use', 'easy'],
    repurchase: ['재구매', '추천', '또 살', 'recommend', 'buy again']
  };

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const text = (node) => String(node?.textContent || '').replace(/\s+/g, ' ').trim();

  const firstText = (selectors, max = 500) => {
    for (const selector of selectors || []) {
      const node = document.querySelector(selector);
      const value = text(node);
      if (value) return value.slice(0, max);
    }
    return '';
  };

  const visible = (el) => {
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };

  const extractReviews = () => {
    const selectors = CONFIG[PLATFORM]?.review || [];
    const seen = new Set();
    const samples = [];
    for (const selector of selectors) {
      for (const el of document.querySelectorAll(selector)) {
        if (!visible(el)) continue;
        const value = text(el);
        if (value.length < 12) continue;
        const snippet = value.slice(0, MAX_SNIPPET);
        if (seen.has(snippet)) continue;
        seen.add(snippet);
        samples.push({ text: snippet });
        if (samples.length >= MAX_REVIEWS) return samples;
      }
    }
    return samples;
  };

  const clusterSignals = (samples) => {
    const counts = Object.fromEntries(Object.keys(CLUSTERS).map((key) => [key, 0]));
    for (const sample of samples) {
      const lower = sample.text.toLowerCase();
      for (const [cluster, words] of Object.entries(CLUSTERS)) {
        if (words.some((word) => lower.includes(word.toLowerCase()))) counts[cluster] += 1;
      }
    }
    return counts;
  };

  const parsePriceHints = (raw) => {
    const value = String(raw || '');
    const krw = value.match(/₩\s?([0-9,]+)/);
    if (krw) return { currency: 'KRW', amount: Number(krw[1].replace(/,/g, '')) };
    const usd = value.match(/\$\s?([0-9,.]+)/);
    if (usd) return { currency: 'USD', amount: Number(usd[1].replace(/,/g, '')) };
    return { currency: null, amount: null };
  };

  const productId = () => {
    if (PLATFORM === 'COUPANG') return location.pathname.match(/\/products\/(\d+)/)?.[1] || '';
    if (PLATFORM === 'ALIEXPRESS') return location.pathname.match(/item\/(\d+)\.html/)?.[1] || '';
    if (PLATFORM === 'AMAZON') return location.pathname.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/)?.[1] || '';
    return '';
  };

  const getParams = (input = {}) => {
    const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
    return {
      appId: String(input.appId || hash.get('appId') || 'ALL_APPS').slice(0, 80),
      query: String(input.query || hash.get('query') || '').slice(0, 180),
      taskId: String(input.taskId || hash.get('taskId') || '').slice(0, 120)
    };
  };

  const scrollToReviews = () => {
    for (const selector of CONFIG[PLATFORM]?.reviewAnchor || []) {
      const node = document.querySelector(selector);
      if (node) {
        node.scrollIntoView({ block: 'start', behavior: 'smooth' });
        return;
      }
    }
  };

  async function scan(input = {}) {
    if (!CONFIG[PLATFORM]) return { ok: false, error: 'UNSUPPORTED_PLATFORM' };

    const params = getParams(input);
    scrollToReviews();
    await sleep(800);

    let reviews = [];
    let stable = 0;
    let lastCount = -1;
    for (let i = 0; i < MAX_SCROLLS; i += 1) {
      reviews = extractReviews();
      stable = reviews.length === lastCount ? stable + 1 : 0;
      lastCount = reviews.length;
      if (reviews.length >= MAX_REVIEWS || stable >= 3) break;
      window.scrollBy({ top: Math.max(550, window.innerHeight * 0.75), behavior: 'smooth' });
      await sleep(WAIT_MS);
    }

    const cfg = CONFIG[PLATFORM];
    const rawPrice = firstText(cfg.price, 160);
    const deliveryText = firstText(cfg.delivery, 300);
    const priceHint = parsePriceHints(rawPrice);
    const payload = {
      schemaVersion: 'CENTRAL_SHOPPING_RESEARCH_V1',
      appId: params.appId,
      taskId: params.taskId || undefined,
      query: params.query || undefined,
      platform: PLATFORM,
      productId: productId() || undefined,
      productUrl: location.href.split('#')[0],
      title: firstText(cfg.title, 260),
      capturedAt: new Date().toISOString(),
      offerEvidence: {
        rawPriceText: rawPrice || null,
        parsedCurrency: priceHint.currency,
        parsedAmount: priceHint.amount,
        rawDeliveryText: deliveryText || null,
        verifiedDeliverable: null,
        note: 'UI text is research evidence only. Final recommendation requires provider/runtime delivery verification.'
      },
      reviewEvidence: {
        sampleCount: reviews.length,
        signalClusters: clusterSignals(reviews),
        samples: reviews
      },
      lineage: {
        stage: 'QUEENS',
        next: 'DRIVE_SYNC→QUEENS_DEDUP_NOISE_FILTER→SEED_QUALIFICATION→APP_DOMAIN_T1/T2'
      },
      policy: {
        publicVisibleUiOnly: true,
        boundedScroll: true,
        maxScrolls: MAX_SCROLLS,
        maxReviews: MAX_REVIEWS,
        noLoginAutomation: true,
        noCaptchaBypass: true,
        noReviewerIdentity: true,
        singleReviewNeverFact: true,
        recommendationRequiresVerifiedDelivery: true
      }
    };

    chrome.runtime.sendMessage({ type: 'CENTRAL_SHOPPING_RESEARCH_RESULT', payload }, () => {});
    return { ok: true, payload };
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || message.type !== 'CENTRAL_SHOPPING_RESEARCH_SCAN') return;
    scan(message.payload || {}).then(sendResponse).catch((error) => sendResponse({ ok: false, error: String(error) }));
    return true;
  });

  if (location.hash.includes('central-shopping-scan')) {
    scan().catch(() => {});
  }
})();
