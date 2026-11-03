// Original Broomm bridge for Steam's installed SharedJSContext. Data is passed
// as JSON by Dart; this file contains no user-supplied executable JavaScript.
async function broommSteam(request) {
  class BroommSteamError extends Error {}
  const deadline = performance.now() + 20000;
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  const limited = (promise, ms = 12000) => {
    let timer;
    return Promise.race([Promise.resolve(promise), new Promise((_, reject) => {
      timer = setTimeout(() => reject(new BroommSteamError('Steam is still processing this request. Retry Add to Steam.')),
        Math.max(1, Math.min(ms, deadline - performance.now())));
    })]).finally(() => clearTimeout(timer));
  };
  try {
    const state = globalThis.__broommSteamV1 ||= {session: crypto.randomUUID(), jobs: new Map()};
    const account = () => {
      if (performance.now() >= deadline) throw new BroommSteamError('Steam took too long to respond. Retry Add to Steam.');
      if (!globalThis.App?.BHasCurrentUser?.() || !globalThis.appStore?.m_bIsInitialized)
        throw new BroommSteamError('Sign in to Steam and wait for its library to finish loading, then retry.');
      const id = String(App.GetCurrentUser()?.strSteamID || '');
      if (!/^\d{17}$/.test(id)) throw new BroommSteamError('The active Steam account could not be identified.');
      if (request.account && request.account !== id)
        throw new BroommSteamError('The Steam account changed. Retry for the currently signed-in account.');
      return id;
    };
    const user = account();
    const api = globalThis.SteamClient?.Apps;
    for (const method of ['AddShortcut', 'SetShortcutName', 'SetShortcutExe', 'SetShortcutStartDir',
      'SetShortcutLaunchOptions', 'SetShortcutIcon', 'SetCustomArtworkForApp', 'ClearCustomArtworkForApp',
      'SetCustomLogoPositionForApp', 'RegisterForAppDetails']) {
      if (typeof api?.[method] !== 'function') throw new BroommSteamError('This Steam client does not expose the required library APIs. Update Steam and retry.');
    }
    if (request.op === 'context') return {account: user, session: state.session};
    const validId = id => Number.isInteger(id) && id > 0 && id <= 0xffffffff;
    const shortcuts = () => {
      account();
      const map = appStore.m_mapApps;
      // Steam uses an observable map, not necessarily the native Map class.
      if (!map || typeof map.values !== 'function') throw new BroommSteamError('Steam shortcut discovery is unavailable.');
      const entries = [...map.values()];
      if (entries.some(app => typeof app?.BIsShortcut !== 'function'))
        throw new BroommSteamError('Steam library inspection was incomplete.');
      return entries.filter(app => app.BIsShortcut())
        .map(app => app.appid).sort((a, b) => a - b);
    };
    const details = async id => {
      if (!validId(id)) throw new BroommSteamError('Steam returned an invalid shortcut ID.');
      // RequestAppDetails may return an unsubscribed, stale cache. A short-lived
      // native registration gives fresh settings and is always unregistered.
      let registration;
      let d;
      try {
        d = await limited(new Promise(resolve => {
          registration = api.RegisterForAppDetails(id, resolve);
        }));
      } finally { registration?.unregister(); }
      account();
      if (!d || d.unAppID !== id || typeof d.strShortcutExe !== 'string' ||
          typeof d.strShortcutStartDir !== 'string' || typeof d.strShortcutLaunchOptions !== 'string')
        throw new BroommSteamError('Steam has not provided complete shortcut details. Wait for the library and retry.');
      return d;
    };
    const unquote = value => value.startsWith('"') && value.endsWith('"') ? value.slice(1, -1) : value;
    const ours = d => unquote(d.strShortcutExe) === request.target ||
      (d.unAppID === request.id && unquote(d.strShortcutExe) === request.previous);
    if (request.op === 'inspect') {
      const before = shortcuts();
      if (before.length > 2000) throw new BroommSteamError('This Steam library has too many shortcuts to inspect safely.');
      const found = [];
      for (let offset = 0; offset < before.length; offset += 8) {
        const batch = await Promise.all(before.slice(offset, offset + 8).map(details));
        for (const d of batch) {
          if (ours(d)) found.push(d.unAppID);
          else if (d.unAppID === request.id)
            throw new BroommSteamError('The recorded Broomm shortcut now launches another application. It has been kept. Remove Broomm’s Steam receipt before adding a different shortcut.');
        }
      }
      if (JSON.stringify(before) !== JSON.stringify(shortcuts()))
        throw new BroommSteamError('The Steam library changed during inspection. Retry Add to Steam.');
      return {ids: found};
    }
    if (request.op === 'create') {
      // A lost WebSocket does not cancel native AddShortcut. Join the same job
      // on retry, including its resolved ID if appStore has not caught up yet.
      const key = user + ':' + request.token;
      let job = state.jobs.get(key);
      if (!job) {
        if (state.jobs.size >= 32) throw new BroommSteamError('Restart Steam normally before adding another shortcut.');
        account();
        job = {target: request.target};
        job.promise = Promise.resolve(api.AddShortcut('Broomm', request.target, '', request.target))
          .then(id => { if (!validId(id)) throw new BroommSteamError('Steam did not return a shortcut ID.'); return id; });
        state.jobs.set(key, job);
      }
      if (job.target !== request.target) throw new BroommSteamError('A previous Steam shortcut request is still pending. Retry from the original Broomm copy.');
      const id = await limited(job.promise);
      account();
      return {id};
    }
    const id = request.id;
    // Native AddShortcut can resolve before the observable library publishes it.
    for (let attempt = 0; validId(id) && !shortcuts().includes(id) && attempt < 30; attempt++)
      await delay(100);
    const current = await details(id);
    if (!ours(current) || !shortcuts().includes(id))
      throw new BroommSteamError('The Broomm shortcut identity changed. No other application was modified.');
    if (request.op === 'configure') {
      account();
      api.SetShortcutName(id, 'Broomm');
      api.SetShortcutExe(id, '"' + request.target + '"');
      api.SetShortcutStartDir(id, request.directory);
      api.SetShortcutLaunchOptions(id, '');
      api.SetShortcutIcon(id, request.icon);
      for (let attempt = 0; attempt < 30; attempt++) {
        const d = await details(id);
        const directory = value => unquote(value).replace(/[\\/]+$/, '');
        if (appStore.m_mapApps.get(id)?.display_name === 'Broomm' && unquote(d.strShortcutExe) === request.target &&
            directory(d.strShortcutStartDir) === directory(request.directory) && d.strShortcutLaunchOptions === '') return {id};
        await delay(100);
      }
      throw new BroommSteamError('Steam has not confirmed the shortcut settings. Retry Add to Steam.');
    }
    if (request.op === 'artwork') {
      const kinds = {cover: [0, 'p'], horizontal: [3, ''], hero: [1, '_hero'], logo: [2, '_logo']};
      const spec = kinds[request.kind];
      if (!spec || !/^[a-f0-9]{64}$/.test(request.sha256) || typeof request.data !== 'string')
        throw new BroommSteamError('Invalid bundled Steam artwork.');
      const read = async extension => {
        const url = new URL(urlStore.BuildCustomAssetURL(id, spec[1], extension, Date.now()), location.href);
        if (url.origin !== location.origin || !url.pathname.startsWith('/customimages/'))
          throw new BroommSteamError('Steam returned an unsafe artwork address.');
        const abort = new AbortController();
        const timer = setTimeout(() => abort.abort(), 4000);
        try {
          const r = await fetch(url, {cache: 'no-store', signal: abort.signal});
          if (r.status === 404) return null;
          if (!r.ok) throw new BroommSteamError('Steam artwork could not be inspected. Retry Add to Steam.');
          const reader = r.body.getReader();
          const parts = []; let size = 0;
          for (;;) {
            const part = await reader.read();
            if (part.done) break;
            size += part.value.length;
            if (size > 8 * 1024 * 1024) { await reader.cancel(); throw new BroommSteamError('Steam artwork exceeded the size limit.'); }
            parts.push(part.value);
          }
          const data = new Uint8Array(size); let offset = 0;
          for (const part of parts) { data.set(part, offset); offset += part.length; }
          const hash = await crypto.subtle.digest('SHA-256', data);
          return [...new Uint8Array(hash)].map(n => n.toString(16).padStart(2, '0')).join('');
        } finally { clearTimeout(timer); }
      };
      const finish = async () => {
        account();
        if (request.kind === 'logo') await limited(api.SetCustomLogoPositionForApp(id,
          JSON.stringify({nVersion: 1, logoPosition: {pinnedPosition: 'BottomLeft', nWidthPct: 42, nHeightPct: 40}})));
        return {id, verified: true};
      };
      if (await read('png') === request.sha256 && await read('jpg') === null) return await finish();
      account();
      await limited(api.ClearCustomArtworkForApp(id, spec[0]));
      // Clear/readback avoids an older JPG shadowing the new PNG.
      if (await read('png') !== null || await read('jpg') !== null)
        throw new BroommSteamError('Steam has not finished clearing its previous artwork. Retry Add to Steam.');
      account();
      await limited(api.SetCustomArtworkForApp(id, request.data, 'png', spec[0]));
      if (await read('png') !== request.sha256)
        throw new BroommSteamError('Steam has not confirmed the new artwork. The shortcut was kept; retry Add to Steam.');
      return await finish();
    }
    throw new BroommSteamError('Unknown Broomm Steam operation.');
  } catch (error) {
    // Our own actionable errors only; never serialize native exception objects.
    const message = error instanceof Error ? error.message : '';
    const safe = error instanceof BroommSteamError;
    return {error: safe ? message : 'Steam could not complete this operation. The shortcut may already exist; retry Add to Steam.'};
  }
}
