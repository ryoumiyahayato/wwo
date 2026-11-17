
import base64,json,subprocess,sys
repo='ryoumiyahayato/wwo'
branch, base, local, compare, subject=sys.argv[1:]
def gh(*args, data=None):
    return json.loads(subprocess.check_output(['gh','api',*args],
         input=json.dumps(data,ensure_ascii=False).encode() if data is not None else None))
base_remote=gh(f'repos/{repo}/git/ref/heads/{base}')['object']['sha']
gh(f'repos/{repo}/git/refs', '-X','POST','--input','-',data={'ref':f'refs/heads/{branch}','sha':base_remote})
paths=subprocess.check_output(['git','diff','--name-only','-z',compare,local]).decode().rstrip('\0').split('\0')
additions=[{'path':p,'contents':base64.b64encode(subprocess.check_output(['git','show',f'{local}:{p}'])).decode()} for p in paths]
query='mutation($input:CreateCommitOnBranchInput!){createCommitOnBranch(input:$input){commit{oid url}}}'
variables={'input':{'branch': {'repositoryNameWithOwner':repo,'branchName':branch},
                    'expectedHeadOid':base_remote,'message':{'headline':subject},
                    'fileChanges':{'additions':additions}}}
r=gh('graphql','--input','-',data={'query':query,'variables':variables})
print(r['data']['createCommitOnBranch']['commit'])
