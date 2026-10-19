import {createRemoteJWKSet,jwtVerify} from 'jose';
export const audience='https://sfcozzjcuppfypetbbzn.supabase.co/functions/v1/mastercaller-github';
const keys=createRemoteJWKSet(new URL('https://token.actions.githubusercontent.com/.well-known/jwks'),{timeoutDuration:10000});
export async function verifyGitHub(token,key=keys){
 const {payload}=await jwtVerify(token,key,{issuer:'https://token.actions.githubusercontent.com',audience,algorithms:['RS256'],maxTokenAge:'10 minutes',requiredClaims:['exp','iat','sub'],clockTolerance:5});
 if(payload.repository_id!=='1421700405'||payload.repository_owner_id!=='339288382'||payload.repository!=='QUEPARI/predict-webapp'||payload.ref!=='refs/heads/main'||payload.workflow_ref!=='QUEPARI/predict-webapp/.github/workflows/mastercaller-sync.yml@refs/heads/main'||!['push','schedule','workflow_dispatch'].includes(payload.event_name)||payload.runner_environment!=='github-hosted')throw Error('Workflow niet toegestaan');
 return payload;
}
