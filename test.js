const assert=require("assert");
const {spawn}=require("child_process");
const server=spawn(process.execPath,["server.js"],{cwd:__dirname,stdio:"ignore"});
const wait=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{try{
  await wait(900);
  const login=await fetch("http://localhost:4782/api/login",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({email:"owner@aerodesk.local",password:"AeroDesk2026!"})});
  assert.equal(login.status,200);const {token}=await login.json();const headers={"content-type":"application/json",authorization:`Bearer ${token}`};
  const boot=await fetch("http://localhost:4782/api/bootstrap",{headers});assert.equal(boot.status,200);
  const sr=await fetch("http://localhost:4782/api/search",{method:"POST",headers,body:JSON.stringify({origin:"KTM",destination:"DXB",departure:"2026-09-01",adults:1,cabin:"Economy",currency:"USD"})});assert.equal(sr.status,200);const offers=await sr.json();assert.ok(offers.length>=5);
  const customer={name:"Test Passenger",email:"test@example.com",phone:"+9770000000"};
  const br=await fetch("http://localhost:4782/api/bookings",{method:"POST",headers,body:JSON.stringify({offer:offers[0],customer})});assert.equal(br.status,201);const booking=await br.json();
  assert.ok(booking.pnr);const pr=await fetch(`http://localhost:4782/api/bookings/${booking.id}/pay`,{method:"POST",headers,body:JSON.stringify({method:"Agency wallet"})});assert.equal(pr.status,200);
  const tr=await fetch(`http://localhost:4782/api/bookings/${booking.id}/ticket`,{method:"POST",headers,body:"{}"});assert.equal(tr.status,200);const ticket=await tr.json();assert.ok(ticket.ticket);
  console.log("PASS: login, bootstrap, search, booking, payment and ticketing");
}catch(e){console.error("FAIL:",e);process.exitCode=1}finally{server.kill()}})();
