// This pure function is serialized into a Blob worker. WebKit does not load
// Worker scripts directly from every WKURLSchemeHandler custom scheme.
export function searchDocumentText({text,query,matchCase,wholeWord,regex,replacement}){
  try{
    let pattern=regex?query:query.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
    if(wholeWord)pattern=`(?<![\\p{L}\\p{N}_])(?:${pattern})(?![\\p{L}\\p{N}_])`;
    const expression=new RegExp(pattern,'gu'+(matchCase?'':'i')),matches=[];
    for(const match of text.matchAll(expression)){
      if(!match[0].length)continue;
      matches.push({start:match.index,length:match[0].length,text:replacement==null?null:regex?replacement.replace(/\$(\$|&|\d{1,2}|<[^>]+>)/g,(token,key)=>key==='$'?'$':key==='&'?match[0]:key[0]==='<'?match.groups?.[key.slice(1,-1)]??'':match[Number(key)]??token):replacement});
    }
    return {matches};
  }catch(error){return {error:'Invalid regular expression: '+error.message};}
}
