/* V6 presentation adapter. Providers, auth, commands and Job Flow remain in index.html. */
(() => {
  'use strict';
  if (new URLSearchParams(location.search).get('v6') === '0') return;
  document.documentElement.dataset.officeVersion = '6';
  const $ = s => document.querySelector(s);
  const meta = {
    ASTRA: ['Astra', 'Coordinación', '#62b5ff', 'astra'],
    RADAR: ['Radar', 'Inteligencia', '#69adf5', 'radar'],
    EDITOR: ['Editor', 'Estudio creativo', '#f4a45f', 'editor'],
    DIRECTOR: ['Director', 'Dirección', '#f58d7f', 'director'],
    MEASUREMENT: ['Analytics', 'Measurement', '#bd9cff', 'measurement'],
    LEARNING: ['Learning', 'Conocimiento', '#55c6b3', 'learning'],
    FACTORY: ['Factory', 'Producción', '#94cb73', 'factory'],
    GUARDIAN: ['Guardian', 'Protección', '#f0cc62', 'guardian'],
    PUBLISHER: ['Publisher', 'Comunicación', '#f18abd', 'publisher'],
    RECOVERY: ['Recovery', 'Soporte técnico', '#5ed6d9', 'recovery']
  };
  const office = $('#office');
  const data = new Map();
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function evidence(a, now = Date.now()) {
    const status = VALID_STATES.has(a?.status) ? a.status : 'UNKNOWN';
    const time = Date.parse(a?.updated_at || '');
    const supported = a?.source_mode === 'REAL' && status !== 'UNKNOWN' &&
      Number.isFinite(time) && time <= now + 5000 &&
      !['NONE','LOW','MOCK','UNKNOWN',''].includes(String(a?.confidence || '').toUpperCase()) &&
      !!a?.source && !/unavailable|missing|unmapped/i.test(a.source);
    const mode = a?.source_mode === 'MOCK' ? 'MOCK' : supported ? 'REAL' : 'UNKNOWN';
    const fresh = supported && now - time <= 90000;
    const job = a?.current_job || '';
    const working = mode === 'REAL' && fresh && status === 'WORKING' &&
      !!job && !/no current|unavailable|missing|standing by/i.test(job);
    return {mode, status: mode === 'UNKNOWN' ? 'UNKNOWN' : status, working, fresh};
  }
  const icons = {
    office:'M2 2h5v5H2zM10 2h5v5h-5zM2 10h5v5H2zM10 10h5v5h-5z',
    command:'m3 4 4 4-4 4M9 13h5', jobs:'M2 4h5v5H2zM10 9h5v5h-5zM7 6h5v3',
    agents:'M5 2h7v7H5zM3 15v-4h11v4', safety:'M3 3l5-2 6 2v7l-6 5-5-5zM6 8l2 2 3-4',
    settings:'M2 4h13M2 12h13M6 2v4M11 10v4'
  };
  function icon(name) {return `<svg viewBox="0 0 17 17" aria-hidden="true"><path d="${icons[name]}"/></svg>`}
  const nav = $('#office-nav');
  $('#nav-office').innerHTML = icon('office')+'<span>Oficina</span>';
  $('#nav-command').innerHTML = icon('command')+'<span>Command</span>';
  nav.querySelector(':scope > span').remove();
  nav.insertAdjacentHTML('afterbegin', '<div class="v6-nav-brand"><div class="v6-solar-mark" aria-hidden="true"></div><b>SOLAR<br>CONNECTS</b></div><small class="v6-nav-caption">WORKSPACE</small>');
  for (const [id,label] of [['jobs','Jobs'],['agents','Agentes'],['safety','Safety'],['settings','Ajustes']]) {
    const button = document.createElement('button');button.id = 'v6-nav-'+id;button.type = 'button';
    button.innerHTML = icon(id)+`<span>${label}</span>`;nav.appendChild(button);
  }
  nav.insertAdjacentHTML('beforeend','<div class="v6-nav-bottom"><span class="v6-mini-sun"></span><b>Solar Connects</b><small>AI Agent Office · V6</small><span class="v6-readonly">OBSERVACIÓN</span></div>');
  $('header > div:first-child').innerHTML = '<b>SOLAR CONNECTS <em>/</em> AI AGENT OFFICE</b><small>Un lugar para cada agente. Evidencia detrás de cada estado.</small>';
  $('header .live').textContent = 'V6.1 · PIXEL HQ';
  $('header .mock').textContent = 'REAL / MOCK / UNKNOWN';
  $('.sign').innerHTML = '<div><small>SOLAR CONNECTS / WORKSPACE</small><h1>La oficina</h1></div><div class="v6-legend"><span data-mode="REAL">REAL</span><span data-mode="MOCK">MOCK</span><span data-mode="UNKNOWN">UNKNOWN</span></div>';
  const sidebar = $('#office-main > aside');
  sidebar.insertAdjacentHTML('afterbegin','<div class="v6-panel-title"><span>AGENT STATUS</span><small>CANONICAL VIEW</small></div>');
  const safety = document.createElement('section');safety.id = 'v6-safety';safety.className = 'v6-panel';
  // Current canonical agent/job contracts expose no gate snapshot. UI policy constants
  // and IDLE/WORKING agent states are not evidence that an operational gate is OFF.
  safety.innerHTML = '<div class="v6-panel-title"><span>SAFETY</span><small>ESTADO DE GATES</small></div><p>Sin evidencia canónica de gates en los proveedores actuales.</p>'+['Factory','Publisher','Meta Direct','External Write'].map(x=>`<div class="v6-gate"><span>${x}</span><output data-gate="${x}" data-state="UNKNOWN" aria-label="${x}: UNKNOWN, sin evidencia canónica">UNKNOWN</output></div>`).join('')+'<button type="button" class="v6-link" id="v6-safety-open">Ver controles de Safety <span>↗</span></button>';
  sidebar.insertBefore(safety, $('.feedHead'));
  const quick = document.createElement('section');quick.className = 'v6-panel';quick.id = 'v6-quick';
  quick.innerHTML = '<div class="v6-panel-title"><span>QUICK COMMANDS</span><small>NAVEGACIÓN</small></div><button type="button" id="v6-command-open">Abrir Command Center <span>↗</span></button><button type="button" id="v6-jobs-open">Inspeccionar Job Flow <span>→</span></button><p>Los accesos abren paneles. No ejecutan trabajos.</p>';
  sidebar.insertBefore(quick, $('.feedHead'));
  $('.feedHead span').textContent = 'FUENTE IDENTIFICADA';
  const flow = $('#v4-flow-panel');
  $('.world').appendChild(flow);
  flow.insertAdjacentHTML('beforeend','<div id="v6-flow-track" aria-label="Distribución canónica de trabajos"></div>');
  $('.world').appendChild($('#v4-unknown-lane'));
  document.querySelector('footer').innerHTML = '<span>SOLAR CONNECTS · AI AGENT OFFICE V6</span><span>Movimiento sólo con evidencia · MOCK / UNKNOWN estáticos</span><a href="?v6=0">Ver interfaz V5</a>';
  const dialog = document.createElement('dialog');dialog.id = 'v6-settings';dialog.innerHTML = '<form method="dialog"><button class="v6-close" aria-label="Cerrar ajustes">×</button><h2>Ajustes de la oficina</h2><p>V6 es una capa visual reversible.</p><label><input type="checkbox" id="v6-reduce-motion"> Reducir movimiento</label><p>Los agentes MOCK y UNKNOWN siempre están estáticos.</p><a href="?v6=0">Volver a la interfaz V5</a></form>';
  document.body.appendChild(dialog);
  function officeView(target) {$('#nav-office').click();target?.scrollIntoView({block:'nearest'});if(target){target.setAttribute('tabindex','-1');target.focus({preventScroll:true})}}
  function safetyView() {$('#nav-command').click();const card = [...$('#command-view').querySelectorAll('.card')].find(x=>x.querySelector('h2')?.textContent === 'Safety');card?.scrollIntoView({block:'center'});card?.setAttribute('tabindex','-1');card?.focus({preventScroll:true})}
  $('#v6-nav-jobs').onclick = $('#v6-jobs-open').onclick = () => officeView(flow);
  $('#v6-nav-agents').onclick = () => officeView($('#detail'));
  $('#v6-nav-safety').onclick = $('#v6-safety-open').onclick = safetyView;
  $('#v6-command-open').onclick = () => $('#nav-command').click();
  $('#v6-nav-settings').onclick = () => dialog.showModal();
  $('#v6-reduce-motion').onchange = e => document.documentElement.classList.toggle('v6-reduced-motion', e.target.checked);

  function roomMarkup(name) {
    const [label,role] = meta[name];
    return `<div class="v6-room-sign"><b>${esc(label)}</b><span>${esc(role)}</span></div><div class="v6-room-set" aria-hidden="true"><div class="v6-window"><i></i><i></i></div><div class="v6-shelf"><i></i><i></i><i></i><i></i></div><div class="v6-wall-art"></div><div class="v6-plant"><i></i></div>${name==='GUARDIAN'?'<img class="v6-cat" src="v6/sprites/cat.svg" alt="">':''}<span class="v6-floor-light"></span></div><div class="stations"></div><div class="v6-room-status"></div>`;
  }
  function decorate() {
    if (!office.querySelector('.station') || office.firstElementChild?.dataset.v6Room) return;
    const nodes = new Map([...office.querySelectorAll('.station')].map(el=>[el.dataset.agent,el]));
    const rooms = [];
    for (const name of Object.keys(meta)) {
      const el = nodes.get(name);if(!el)continue;
      const room = document.createElement('section');room.className = 'department v6-room v6-'+name.toLowerCase();room.dataset.v6Room = name;
      room.style.setProperty('--agent',meta[name][2]);room.setAttribute('aria-label',meta[name][0]);
      room.innerHTML = roomMarkup(name);
      if(name === 'ASTRA') {
        room.insertAdjacentHTML('afterbegin','<div class="v6-city" aria-hidden="true"><div class="v6-sun"></div><div class="v6-cloud c1"></div><div class="v6-cloud c2"></div><div class="v6-skyline far"></div><div class="v6-skyline near"></div></div><div class="v6-astra-label"><small>ASTRA / COORDINACIÓN</small><strong>COMMAND CENTER</strong><button type="button" class="v61-astra-command">Abrir Command <span>→</span></button></div><div class="v6-astra-plaque">SOLAR<br>CONNECTS</div>');
        room.querySelector('.v61-astra-command').onclick = () => $('#nav-command').click();
      }
      room.querySelector('.stations').appendChild(el);
      if(!el.querySelector('.v6-chair')) el.insertAdjacentHTML('afterbegin','<span class="v6-chair" aria-hidden="true"></span>');
      rooms.push(room);
    }
    // Moving the original buttons preserves onclick, data-agent and Job Flow anchors.
    office.replaceChildren(...rooms);
    paintEvidence();
  }
  function paintEvidence() {
    for(const el of office.querySelectorAll('.station')) {
      const a = data.get(el.dataset.agent);const e = evidence(a);
      el.dataset.v6Source = e.mode;el.dataset.v6Working = String(e.working);
      const badge = el.closest('.v6-room')?.querySelector('.v6-room-status');
      if(badge) {badge.dataset.mode=e.mode;badge.innerHTML=`<span>${e.mode}</span><b>${e.status}</b>${e.mode==='REAL'&&!e.fresh?'<small>sin evidencia reciente</small>':''}`;badge.title = a ? `${a.source} · ${a.updated_at || 'sin fecha'} · ${a.confidence}` : 'Sin evidencia canónica';}
      const state = el.querySelector('.state');if(state) state.textContent=e.status;
      el.setAttribute('aria-label',`${meta[el.dataset.agent]?.[0] || el.dataset.agent} · ${e.mode} · ${e.status}. Ver detalle`);
    }
    const a = data.get($('#detail h2')?.textContent);const e = evidence(a);
    $('#detail').dataset.v6Source = e.mode;$('#detail').dataset.v6Working = String(e.working);
    let label = $('#detail .v6-source-note');
    if(!label){label=document.createElement('div');label.className='v6-source-note';$('#detail').appendChild(label)}
    label.dataset.mode=e.mode;label.textContent = e.mode==='MOCK'?'MOCK · demostración estática':e.mode==='UNKNOWN'?'UNKNOWN · sin evidencia suficiente':e.fresh?'REAL · evidencia canónica reciente':'REAL · evidencia histórica, sin animación';
    if(e.mode==='UNKNOWN') {const s=$('#detail .bigStatus');if(s)s.textContent='UNKNOWN'}
    // Feed provenance comes from the same canonical activity array as the original renderer.
    document.querySelectorAll('#feed .feedItem').forEach((el,i)=>{
      if(el.querySelector('.v6-feed-source'))return;
      const mode = ['REAL','MOCK'].includes(activity[i]?.source_mode)?activity[i].source_mode:'UNKNOWN';
      const tag=document.createElement('small');tag.className='v6-feed-source';tag.dataset.mode=mode;tag.textContent=mode;el.querySelector('b')?.appendChild(tag);
    });
  }
  function paintFlow() {
    const snap=window.__V4_DIAGNOSTICS__?.().provider;
    const jobs=Array.isArray(snap?.jobs)?snap.jobs:[];
    const known = snap?.status==='READY' || jobs.length>0;
    $('#v6-flow-track').innerHTML=['FACTORY','GUARDIAN','PUBLISHER','MEASUREMENT','LEARNING','RECOVERY'].map(name=>{
      const count=jobs.filter(j=>j.source_mode==='REAL'&&j.current_agent===name&&j.lifecycle!=='DELETED').length;
      return `<div style="--agent:${meta[name][2]}"><span>${meta[name][0]}</span><b>${known?count:'—'}</b><small>${known?'REAL JOBS':'UNKNOWN'}</small></div>`;
    }).join('');
  }
  function accept(rows) {rows.forEach(a=>data.set(a.name,{...a}));decorate();paintEvidence();paintFlow()}
  provider.subscribeToChanges(async rows => accept(await rows));
  const observer=new MutationObserver(()=>{decorate();paintEvidence()});
  observer.observe(office,{childList:true});
  new MutationObserver(paintEvidence).observe($('#detail'),{childList:true});
  new MutationObserver(paintEvidence).observe($('#feed'),{childList:true});
  for(const selector of ['#v4-real-count','#v4-freshness']) new MutationObserver(paintFlow).observe($(selector),{childList:true,subtree:true});
  // Render UNKNOWN while the existing provider performs its first read; no invented activity.
  if(!office.querySelector('.station')) render(Object.entries(meta).map(([name,m])=>normalizeAgent({name,avatar:m[3],dept:name==='ASTRA'?'ENGINEERING':name==='RADAR'?'INTELLIGENCE':['EDITOR','DIRECTOR'].includes(name)?'CREATIVE':META[name]?.dept,source_mode:'UNKNOWN',status:'UNKNOWN',confidence:'NONE'})));
  decorate();paintFlow();
  provider.getAgents().then(accept);
  setInterval(()=>{paintEvidence();paintFlow()},5000);
  window.__V6_OFFICE__=Object.freeze({version:'6.1.0',evidence,enabled:true,rollback:'?v6=0',snapshot:()=>Object.fromEntries([...data].map(([name,a])=>[name,evidence(a)]))});
})();
