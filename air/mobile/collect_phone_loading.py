"""Copy only the app's local numeric diagnostics from the physical test iPhone.
No console stream, packet capture, screenshots, credentials or message content.
"""
from pathlib import Path
import argparse,json,subprocess,tempfile
from datetime import datetime,timezone
DEVICE='00008120-000E70543633401E'
APP='org.ekoloko.mobilephone'
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 with tempfile.TemporaryDirectory(prefix='ekoloko-phone-metrics-') as name:
  raw=Path(name)/'diagnostics.json'
  subprocess.run(['xcrun','devicectl','device','copy','from','--device',DEVICE,'--domain-type','appDataContainer','--domain-identifier',APP,'--source','Library/Application Support/'+APP+'/Local Store/last-native-diagnostics.json','--destination',str(raw),'--quiet'],check=True)
  data=json.loads(raw.read_text())
 safe={'collectedAt':datetime.now(timezone.utc).isoformat(),'deviceKind':'physical','runtime':data.get('runtime'),'performance':{},'events':[],
       'fatalFailurePresent':any(data.get(k) is not None for k in ('releaseFailure','assetFailure','runtimeFailure'))}
 for k,v in data.get('performance',{}).items():
  if not k.startswith(('socket_','asset_','bootstrap_')):continue
  safe['performance'][k]={n:v[n] for n in ('count','totalMs','maxMs','bytes','maxBytes','slowCount') if isinstance(v.get(n),(int,float))}
 for e in data.get('events',[]):
  if isinstance(e.get('atMs'),(int,float)) and isinstance(e.get('reason'),str):
   safe['events'].append({'reason':e['reason'],'atMs':e['atMs']})
 safe['socketTelemetryPresent']=any(k.startswith('socket_') for k in safe['performance'])
 safe['freshness']='Requires correlation with the confirmed new launch; app data survives reinstall'
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(safe,indent=2)+'\n')
 print(json.dumps(safe,indent=2))
if __name__=='__main__':main()
