import re,subprocess,tempfile
from pathlib import Path
base=Path(__file__).resolve().parents[1]
runner=r'''
let scope = "{\"agent\":\"a\",\"operation\":\"file.write\",\"host\":\"api-host\",\"resource\":\"/private/report.md\"}"
let approval = "{\"id\":\"approval\",\"responsibility\":\"goal\",\"fingerprint\":\"v1\",\"status\":\"pending\",\"preview\":{\"summary\":\"Save note\",\"details\":\"Review\"},\"scope\":"+scope+"}"
let steering = "{\"id\":\"question\",\"agent\":\"a\",\"goal_id\":\"goal\",\"question\":\"Which deadline?\",\"revision\":\"v2\",\"status\":\"pending\"}"
let peer = "{\"instance_id\":\"local\",\"approvals\":["+approval+"],\"steering\":["+steering+"]}"
let text = "{\"instance_id\":\"hub\",\"approvals\":[],\"steering\":[],\"peers\":["+peer+"]}"
let inbox = try JSONDecoder().decode(AutonomyInbox.self, from: Data(text.utf8))
precondition(inbox.peers?.first?.steering.first?.goalID == "goal")
let snapshot = try JSONSerialization.jsonObject(with: JSONEncoder().encode(inbox.directSnapshot)) as! [String:Any]
precondition(snapshot["peers"] == nil)
let decision = try JSONDecoder().decode(AutonomyInboxDecision.self, from: Data("{\"kind\":\"steering\",\"answer\":\"Friday\",\"revision\":\"v2\"}".utf8))
precondition(decision.answer == "Friday")
let legacy = "{\"id\":\"goal\",\"agent\":\"a\",\"goal\":\"Watch\",\"status\":\"paused\",\"phase\":\"idle\",\"interval_seconds\":3600,\"report\":\"\",\"error\":\"\"}"
let goal = try JSONDecoder().decode(AutonomyResponsibility.self, from: Data(legacy.utf8))
precondition(goal.heartbeat == nil && goal.autonomousInstructions == nil)
print("Always-On native contracts passed")
'''
for platform in ("native",):
 source=(base/'WeeOrchestrator/Models/WeeModels.swift').read_text()
 types=[]
 for name in ['AutonomyScope','AutonomyPreview','AutonomyApproval','AutonomyResponsibility','AutonomyGoalSource','AutonomyHeartbeat','AutonomySteering','AutonomyInbox','AutonomyInboxDecision']:
  match=re.search(r'^struct '+name+r'\s*:',source,re.M);start=match.start();opened=source.index('{',start);depth=1;cursor=opened+1
  while depth:
   if source[cursor]=='{':depth+=1
   elif source[cursor]=='}':depth-=1
   cursor+=1
  types.append(source[start:cursor])
 with tempfile.TemporaryDirectory() as directory:
  main=Path(directory)/'main.swift';main.write_text('import Foundation\n'+'\n'.join(types)+'\n'+runner)
  subprocess.run(['swiftc',str(main),'-o',directory+'/check'],check=True)
  subprocess.run([directory+'/check'],check=True)
