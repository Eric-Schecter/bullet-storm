import io, urllib.request, zipfile, pathlib, concurrent.futures
URL='https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
class Remote(io.RawIOBase):
 def __init__(self):
  self.pos=0
  req=urllib.request.Request(URL,headers={'Range':'bytes=0-0','User-Agent':'Bullet-Storm-Web-Export'})
  with urllib.request.urlopen(req,timeout=60) as r:
   if r.status !=206: raise RuntimeError('Server does not support range requests')
   self.size=int(r.headers['Content-Range'].split('/')[-1]);r.read()
 def seekable(self):return True
 def readable(self):return True
 def tell(self):return self.pos
 def seek(self,offset,whence=0):
  self.pos=offset if whence==0 else self.pos+offset if whence==1 else self.size+offset
  return self.pos
 def read(self,n=-1):
  end=self.size-1 if n<0 else min(self.size-1,self.pos+n-1)
  if self.pos>end:return b''
  def fetch(bounds):
   start,stop=bounds
   req=urllib.request.Request(URL,headers={'Range':f'bytes={start}-{stop}','User-Agent':'Bullet-Storm-Web-Export','Cache-Control':'no-cache'})
   with urllib.request.urlopen(req,timeout=60) as r:
    if r.status!=206:raise RuntimeError('Range request failed')
    result=r.read(stop-start+1)
   if len(result)!=stop-start+1:raise RuntimeError('Incomplete range')
   return result
  if end-self.pos>2*1024*1024:
   chunks=[(i,min(end,i+1024*1024-1)) for i in range(self.pos,end+1,1024*1024)]
   parts=[]
   with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    for i,result in enumerate(pool.map(fetch,chunks)):
     parts.append(result)
     print('Downloaded',i+1,'/',len(chunks),'MB chunks',flush=True)
   data=b''.join(parts)
  else:data=fetch((self.pos,end))
  self.pos+=len(data)
  return data
with zipfile.ZipFile(Remote()) as z:
 names=[n for n in z.namelist() if 'web' in n.lower() and n.endswith('.zip')]
 print('Web templates:',names,flush=True)
 for n in names:
  if n == 'templates/web_nothreads_release.zip':
   print('Fetching',n,z.getinfo(n).compress_size,'compressed bytes',flush=True)
   out=pathlib.Path('.export_templates')/pathlib.Path(n).name
   out.parent.mkdir(parents=True,exist_ok=True)
   out.write_bytes(z.read(n)); print('Saved',out,out.stat().st_size,flush=True)
