import copy,unittest
from validate_living import load,validate
class Content(unittest.TestCase):
 def test_valid(self):self.assertEqual(validate(*(load(n) for n in ['living','balance','governance','land'])),[])
 def test_invalid(self):
  for kind in ['duplicate','household','post','discovery','condition','stock','capacity','tuning','unknown']:
   d,b,g,l=(load(n) for n in ['living','balance','governance','land'])
   if kind=='duplicate':d['areas'].append(copy.deepcopy(d['areas'][0]))
   if kind=='household':d['households'][0]['id']='missing'
   if kind=='post':d['posts'][0]['project']='missing'
   if kind=='discovery':d['discoveries'][0]['subjects']=['missing']
   if kind=='condition':d['discoveries'][0]['condition']='random'
   if kind=='stock':d['areas'][0]['recovery']=999
   if kind=='capacity':b['living']['shared_workers']=1
   if kind=='tuning':b['living']['wear_period']=0
   if kind=='unknown':d['secret_bonus']=10
   self.assertTrue(validate(d,b,g,l),kind)
if __name__=='__main__':unittest.main()
