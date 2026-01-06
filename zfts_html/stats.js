//--------------------------------------------------------------------
// Dual Instance File Transfer Monitor (Ground + Air)
// 01‑2026 – Polling only + adjustable frequency + intelligent buttons
//--------------------------------------------------------------------

let airHost = null;
let airPingTimer = null, groundPingTimer = null;
let airUpdateTimer = null, groundUpdateTimer = null;
let airAvailable = true;
let groundAvailable = true;
let airPollInterval = 5000;
let groundPollInterval = 5000;

// Track per-file pending actions
const pendingActions = {};

// ---------- Generic utilities ----------
function formatFileSize(bytes){
  if(bytes>=1e9)return(bytes/1e9).toFixed(2)+" GB";
  if(bytes>=1e6)return(bytes/1e6).toFixed(2)+" MB";
  if(bytes>=1e3)return(bytes/1e3).toFixed(2)+" KB";
  return bytes+" B";
}
function getRateText(r){
  if(r/1e9>1)return(r/1e9).toFixed(3)+" GB/s";
  if(r/1e6>1)return(r/1e6).toFixed(3)+" MB/s";
  if(r/1e3>1)return(r/1e3).toFixed(3)+" KB/s";
  return r.toFixed(3)+" B/s";
}
function getRemainingTime(e){
  if(e.rate===0)return"∞";
  const s=(e.file_size-e.bytes_received)/e.rate;
  const d=new Date(null);d.setSeconds(s);
  return d.toISOString().substr(11,8);
}
function showTableError(tableId,message){
  const t=document.getElementById(tableId); if(!t)return;
  const body=t.tBodies[0]||t.createTBody();
  body.innerHTML="";
  const row=body.insertRow();
  const cell=row.insertCell();
  cell.colSpan=9;
  cell.textContent=message;
  cell.style.textAlign="center";
  cell.style.color="#cc0000";
  cell.style.fontWeight="bold";
}

// ---------- Health / Buttons ----------
function setAirHealth(st,txt){
  const i=document.getElementById("airHealth");
  i.textContent=txt;i.className="";
  i.classList.add(st==="idle"?"health-idle":
    st==="connecting"?"health-connecting":
    st==="ok"?"health-ok":"health-fail");
}
function setConnectBtn(enabled,text){
  const b=document.getElementById("setAirBtn");
  b.disabled=!enabled;b.textContent=text;
}
function setGroundHealth(st,txt){
  const g=document.getElementById("groundHealth");
  g.textContent=txt;g.className="";
  g.classList.add(st==="ok"?"health-ok":
    st==="fail"?"health-fail":"health-idle");
}

// ---------- Fetch & Rendering ----------
function fetchInstance(base,tableId,label){
  fetch(base,{cache:"no-store"})
    .then(r=>r.json())
    .then(d=>renderInstance(d,tableId,label))
    .catch(()=>showTableError(tableId,`${label} service unreachable — displaying no data`));
}

function renderInstance(d,tid,label){
  const t=document.getElementById(tid);
  if(!t)return;
  if(d.platform_name){
    let headerId=`${tid}_platformHeader`;
    let header=document.getElementById(headerId);
    if(!header){
      header=document.createElement("div");
      header.id=headerId;
      header.style.margin="6px 0";
      header.style.fontWeight="bold";
      header.style.color="#1589ff";
      t.insertAdjacentElement("beforebegin",header);
    }
    header.textContent=`Sending Platform Name: ${d.platform_name}`;
  }
  if(!t.tHead){
    const h=["FileID","File Name","State","Complete (%)",
      "Transfer Rate","Time Remaining","File Size","Priority","Actions"];
    const thead=t.createTHead();const r=thead.insertRow();
    h.forEach(c=>{const th=document.createElement("th");th.textContent=c;r.appendChild(th);});
  }
  generateTable(t,d.status||[],label);
}

// ---------- Generate table ----------
function generateTable(table,data,label){
  const body=table.tBodies[0]||table.createTBody();
  body.innerHTML="";
  if(!data||data.length===0){
    const row=body.insertRow();
    const cell=row.insertCell();
    cell.colSpan=9;
    cell.textContent="No files currently in the transfer queue";
    cell.style.textAlign="center";
    cell.style.color="#666";
    cell.style.fontStyle="italic";
    return;
  }

  const localPending=pendingActions;
  data.forEach(e=>{
    const fid=e.fileID;
    const row=body.insertRow();
    row.insertCell().textContent=fid;
    row.insertCell().textContent=e.file_name;

    // ✅ fixed logic: rely primarily on numeric flag
    const inProgress = Number(e.started) === 1;

    row.insertCell().textContent=inProgress?"Running":"Stopped";
    row.insertCell().textContent=e.percent_complete.toFixed(2)+" %";
    row.insertCell().textContent=getRateText(
      typeof e.rate==="object"?parseFloat(e.rate.parsedValue||0):e.rate
    );
    row.insertCell().textContent=getRemainingTime(e);
    row.insertCell().textContent=formatFileSize(e.file_size);

    const priCell=row.insertCell();
    const sel=document.createElement("select");
    sel.id=`${label}_${fid}_priSelect`;
    for(let i=1;i<=5;i++){
      const opt=document.createElement("option");
      opt.value=i;opt.text=i;if(i===e.priority)opt.selected=true;
      sel.add(opt);
    }
    const unavailable=(label==="Air"&&!airAvailable)||(label==="Ground"&&!groundAvailable);
    if(unavailable){sel.disabled=true;sel.style.opacity=0.5;sel.title="Unavailable — source service offline";}
    sel.onchange=()=>handlePriorityChange(e,label);
    priCell.appendChild(sel);

    const action=localPending[fid]||null;
    const isStarting=action==="starting";
    const isStopping=action==="stopping";
    const isCancelling=action==="cancelling";

    const act=row.insertCell();
    const makeBtn=(txt,disabled,cls)=>{
      const b=document.createElement("button");
      b.textContent=txt;
      if(disabled)b.disabled=true;
      if(cls)b.classList.add(cls);
      b.onclick=()=>handleAction(e,txt,label,b);
      return b;
    };

    // START
    const sTxt=isStarting?"Sending…":"Start";
    const startBtn=makeBtn(sTxt,inProgress||isStarting,"");
    if(isStarting)startBtn.classList.add("sending");
    act.appendChild(startBtn);

    // STOP
    const stopTxt=isStopping?"Stopping…":"Stop";
    const stopBtn=makeBtn(stopTxt,!inProgress||isStopping,"");
    if(isStopping)stopBtn.classList.add("stopping");
    act.appendChild(stopBtn);

    // CANCEL
    const cancelTxt=isCancelling?"Cancelling…":"Cancel";
    const cancelBtn=makeBtn(cancelTxt,isCancelling,"");
    if(isCancelling)cancelBtn.classList.add("cancelling");
    act.appendChild(cancelBtn);

    if(isStarting&&inProgress)delete localPending[fid];
    if(isStopping&&!inProgress)delete localPending[fid];
  });

  // cleanup cancelled rows
  const ids=data.map(x=>x.fileID);
  Object.keys(localPending).forEach(fid=>{
    if(localPending[fid]==="cancelling"&&!ids.includes(parseInt(fid)))delete localPending[fid];
  });
}

// ---------- Air connect ----------
function getOrCreatePingDisplay(){
  let el=document.getElementById("latencyDisplay");
  if(!el){
    el=document.createElement("span");
    el.id="latencyDisplay";
    el.style.marginLeft="12px";
    el.style.fontWeight="bold";
    document.getElementById("airControls").appendChild(el);
  }
  return el;
}
function setAirHost(){
  const btn=document.getElementById("setAirBtn");
  if(btn.textContent==="Disconnect"){disconnectAir();return;}
  const host=document.getElementById("airHost").value.trim();
  const msg=document.getElementById("airStatus");
  const ping=getOrCreatePingDisplay();
  if(!host){
    msg.textContent="⚠️ Enter a hostname or IP";
    setAirHealth("idle","🟦 Idle");
    ping.textContent="Ping: N/A";
    return;
  }

  airHost=host;localStorage.setItem("airHost",host);
  msg.textContent="Connecting…";
  setAirHealth("connecting","🟨 Connecting…");
  setConnectBtn(false,"Connecting…");
  ping.textContent="Ping: ...";

  const base=`/airproxy?target=${airHost}:19712&path=files`;
  const start=performance.now();

  fetch(base)
    .then(r=>{if(!r.ok)throw new Error();return r.json();})
    .then(data=>{
      ping.textContent=`Ping: ${Math.round(performance.now()-start)} ms`;
      msg.textContent="✅ Connected";
      setAirHealth("ok","🟩 Connected");
      setConnectBtn(true,"Disconnect");
      renderInstance(data,"airTable","Air");
      airAvailable=true;
      startAirUpdater(base);
      startAirPinger(base,ping);
    })
    .catch(()=>{
      msg.textContent="❌ Connection failed";
      setAirHealth("fail","🟥 Unreachable");
      setConnectBtn(true,"Connect");
      ping.textContent="Ping: N/A";
      airAvailable=false;
      showTableError("airTable","Air service unreachable — displaying no data");
    });
}
function disconnectAir(){
  document.getElementById("airStatus").textContent="Disconnected";
  setAirHealth("idle","🟦 Idle");
  airAvailable=false;
  [airPingTimer,airUpdateTimer].forEach(t=>{if(t)clearInterval(t);});
  airHost=null;
  const p=document.getElementById("latencyDisplay");
  if(p)p.textContent="Ping: N/A";
  setConnectBtn(true,"Connect");
}

// ---------- Updaters ----------
function startAirUpdater(base){
  if(airUpdateTimer)clearInterval(airUpdateTimer);
  airUpdateTimer=setInterval(()=>fetchInstance(base,"airTable","Air"),airPollInterval);
}
function startGroundUpdater(){
  if(groundUpdateTimer)clearInterval(groundUpdateTimer);
  groundUpdateTimer=setInterval(()=>fetchInstance("/files","groundTable","Ground"),groundPollInterval);
}

// ---------- Poll selectors ----------
document.addEventListener("change",e=>{
  if(e.target.id==="airPoll"){
    airPollInterval=parseInt(e.target.value)*1000;
    if(airHost)startAirUpdater(`/airproxy?target=${airHost}:19712&path=files`);
  }
  if(e.target.id==="groundPoll"){
    groundPollInterval=parseInt(e.target.value)*1000;
    startGroundUpdater();
  }
});

// ---------- Pingers ----------
function startAirPinger(base,pingEl){
  if(airPingTimer)clearInterval(airPingTimer);
  let act=false;
  airPingTimer=setInterval(async()=>{
    if(act)return;act=true;
    const ctrl=new AbortController();
    const timeout=setTimeout(()=>ctrl.abort(),8000);
    try{
      const t0=performance.now();
      const r=await fetch(base,{cache:"no-store",signal:ctrl.signal});
      clearTimeout(timeout);
      const ms=Math.round(performance.now()-t0);
      if(!r.ok)throw new Error();
      pingEl.textContent=`Ping: ${ms} ms`;
      airAvailable=true;setAirHealth("ok","🟢 Live");
    }catch{
      clearTimeout(timeout);
      pingEl.textContent="Ping: ❌";
      airAvailable=false;setAirHealth("fail","🔴 Lost");
    }finally{act=false;}
  },10000);
}
function startGroundPinger(){
  if(groundPingTimer)clearInterval(groundPingTimer);
  let act=false;
  const gPing=document.getElementById("groundLatency");
  const gStatus=document.getElementById("groundStatus");
  groundPingTimer=setInterval(async()=>{
    if(act)return;act=true;
    const ctrl=new AbortController();
    const timeout=setTimeout(()=>ctrl.abort(),8000);
    try{
      const t0=performance.now();
      const r=await fetch("/files",{cache:"no-store",signal:ctrl.signal});
      clearTimeout(timeout);
      const ms=Math.round(performance.now()-t0);
      if(!r.ok)throw new Error();
      gPing.textContent=`Ping: ${ms} ms`;
      gStatus.textContent="Ready";
      setGroundHealth("ok","🟢 Active");
      groundAvailable=true;
    }catch{
      clearTimeout(timeout);
      gPing.textContent="Ping: ❌";
      gStatus.textContent="Error reaching Ground";
      setGroundHealth("fail","🔴 Error");
      groundAvailable=false;
    }finally{act=false;}
  },10000);
}

// ---------- Ground init ----------
function initGround(){
  fetchInstance("/files","groundTable","Ground");
  startGroundPinger();
  startGroundUpdater();
}

// ---------- Actions ----------
async function handleAction(e,action,label,btn){
  const fid=e.fileID;
  const isAir=(label==="Air"&&airHost);
  const base=isAir?`/airproxy?target=${airHost}:19712`:"";
  const url=isAir?`${base}&path=files/${fid}`:`/files/${fid}`;
  const priSel=document.getElementById(`${label}_${fid}_priSelect`);
  const p=priSel?parseInt(priSel.value):e.priority;

  let payload={};
  if(action==="Start")payload={started:"true",priority:p};
  else if(action==="Stop")payload={started:"false",cancel:"false"};
  else if(action==="Cancel")payload={started:"false",cancel:"true"};

  pendingActions[fid]=action.toLowerCase()+"ing";
  btn.classList.remove("sending","stopping","cancelling");
  btn.classList.add(action==="Start"?"sending":action==="Stop"?"stopping":"cancelling");
  btn.disabled=true;
  btn.textContent=action==="Start"?"Sending…":action==="Stop"?"Stopping…":"Cancelling…";

  try{
    await fetch(url,{
      method:"POST",
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify(payload),
    });
  }catch(err){
    console.warn(`${label} ${action} failed:`,err);
  }
}

async function handlePriorityChange(e,label){
  const isAir=(label==="Air"&&airHost);
  const url=isAir
    ?`/airproxy?target=${airHost}:19712&path=files/${e.fileID}`
    :`/files/${e.fileID}`;
  const s=document.getElementById(`${label}_${e.fileID}_priSelect`);
  const p=parseInt(s.value);
  await fetch(url,{
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify({started:"true",priority:p})
  });
}

// ---------- User info ----------
function loadUserInfo(){
  fetch("/userinfo",{cache:"no-store"})
    .then(r=>{if(!r.ok)throw new Error();return r.json();})
    .then(u=>{
      const usernameEl=document.getElementById("username");
      const dnEl=document.getElementById("userdn");
      let clean=u.cn||"";clean=clean.replace(/\.\d+$/,"");
      const parts=clean.split(".").filter(p=>p&&!/^\d+$/.test(p));
      let disp=clean;
      if(parts.length>=2){
        const first=parts[1],last=parts[0];
        disp=first.charAt(0).toUpperCase()+first.slice(1).toLowerCase()+" "+last.charAt(0).toUpperCase()+last.slice(1).toLowerCase();
      }
      usernameEl.textContent=disp||"Unknown User";
      usernameEl.title=u.dn||"";dnEl.textContent="";
    })
    .catch(()=>{
      document.getElementById("username").textContent="Unknown User";
      document.getElementById("userdn").textContent="";
    });
}

// ---------- Init ----------
document.addEventListener("DOMContentLoaded",loadUserInfo);
document.addEventListener("DOMContentLoaded",initGround);
document.addEventListener("DOMContentLoaded",()=>{
  const saved=localStorage.getItem("airHost");
  if(saved){
    document.getElementById("airHost").value=saved;
    setTimeout(()=>setAirHost(),600);
  }
});
