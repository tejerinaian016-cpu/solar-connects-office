/* Original Solar Connects pixel artwork. Integer grid, no fonts or remote assets. */
const fs = require('node:fs');
const path = require('node:path');
const dir = path.join(__dirname, '../v6/sprites');
fs.mkdirSync(dir, {recursive:true});
const ink='#263448', skin='#edb387', light='#ffdab2', shadow='#c77e69';
let pixels=[];
function r(x,y,w,h,c){pixels.push(`<path fill="${c}" d="M${x} ${y}h${w}v${h}H${x}z"/>`)}
function box(x,y,w,h,c){r(x,y,w,h,ink);r(x+2,y+2,w-4,h-4,c)}
function boots(){r(14,43,8,8,ink);r(26,43,8,8,ink);r(12,50,10,4,ink);r(26,50,12,4,ink);r(14,50,6,1,'#83929c');r(28,50,6,1,'#83929c')}
function human(color,dark,hair){
 boots();box(11,28,26,18,color);r(14,30,3,12,dark);r(31,31,4,13,dark);r(21,29,6,3,light);r(22,34,4,9,'#f9e6c7');r(24,35,1,7,dark);
 box(9,12,30,20,skin);r(13,15,21,10,light);r(32,18,5,10,skin);r(15,25,17,4,skin);r(16,19,3,3,ink);r(29,19,3,3,ink);r(23,21,2,3,shadow);r(21,27,7,1,'#92596a');r(13,24,4,2,'#e88f7c');r(31,24,3,2,'#e88f7c');
 r(11,7,24,5,ink);r(8,11,31,5,ink);r(11,9,23,5,hair);r(10,14,5,6,hair);r(32,14,5,4,hair);r(15,11,8,5,hair);
 box(5,31,8,13,color);r(7,40,4,5,skin);box(35,31,8,13,color);r(37,40,4,5,light);
}
function headset(c){r(6,12,3,12,ink);r(39,12,3,12,ink);r(10,5,28,3,ink);r(8,8,3,7,c);r(37,8,3,7,c);box(4,17,8,10,c);box(37,17,8,10,c);r(40,26,2,4,ink);r(30,28,11,2,ink);r(28,27,5,3,'#ffe9ba')}
function robot(color,blue){
 boots();box(12,29,25,17,'#dce8e6');r(15,31,4,10,'#fff4d7');r(31,33,4,10,'#99b4bd');box(18,32,13,9,blue);r(22,35,5,3,color);r(22,42,6,3,blue);
 box(7,9,35,22,'#dce8e6');r(10,11,29,4,'#fff4d7');r(37,15,3,12,'#9bb4bf');box(11,16,27,10,blue);r(15,19,5,3,color);r(29,19,5,3,color);r(21,27,8,2,blue);r(21,3,7,7,ink);r(23,2,3,5,color);
 box(4,30,8,15,'#dce8e6');r(6,33,4,3,color);box(37,30,8,15,'#dce8e6');r(39,33,4,3,color);r(6,44,6,3,blue);r(37,44,6,3,blue);
}
function save(name,label){fs.writeFileSync(path.join(dir,name+'.svg'),`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 56" shape-rendering="crispEdges" role="img"><title>${label}</title>${pixels.join('')}</svg>\n`);pixels=[]}
human('#518dda','#34639c','#493d48');headset('#73b8ed');r(16,8,5,2,'#766071');save('radar','Radar · auriculares azules');
human('#e7944f','#b96538','#744c34');r(12,17,24,2,ink);box(13,17,9,7,'#f6e7c4');box(26,17,9,7,'#f6e7c4');r(16,19,3,3,ink);r(29,19,3,3,ink);r(22,19,4,2,ink);r(39,27,3,15,'#f4d15e');r(39,24,3,3,'#edab89');r(40,42,1,3,ink);r(15,36,5,3,'#f4d15e');save('editor','Editor · anteojos y lápiz');
human('#da796e','#ac585b','#b7bbc3');r(13,9,20,3,'#e0e1db');r(10,14,5,7,'#a7aab5');r(34,14,3,8,'#e0e1db');box(25,32,17,15,'#3f596e');r(28,35,11,7,'#9bd5d3');r(30,37,7,1,'#f9ecc9');r(31,44,5,1,'#b7bbc3');r(24,38,4,5,light);save('director','Director · cabello gris y tablet');
boots();box(11,25,27,22,'#8c77bb');r(15,28,19,13,'#c2a7d2');r(18,30,3,3,'#765fa0');r(27,30,3,3,'#765fa0');r(22,37,4,3,'#765fa0');r(8,6,8,15,ink);r(33,6,8,15,ink);r(10,8,6,10,'#9278b1');r(33,8,6,10,'#9278b1');box(8,13,34,19,'#9b81bc');box(10,16,14,13,'#f4dec3');box(26,16,14,13,'#f4dec3');r(15,19,6,7,'#694e8b');r(29,19,6,7,'#694e8b');r(17,20,3,4,ink);r(30,20,3,4,ink);r(17,20,1,2,'#fff');r(30,20,1,2,'#fff');r(22,25,6,3,'#eeb967');r(24,28,2,3,'#eeb967');box(4,31,9,13,'#7861a0');box(37,31,8,13,'#7861a0');r(13,50,8,3,'#eeb967');r(27,50,8,3,'#eeb967');save('measurement','Analytics · búho analítico');
human('#49a9a5','#2d777f','#3c3a43');r(10,10,5,21,'#3c3a43');r(33,12,6,22,'#3c3a43');box(10,32,28,16,'#ecd5a6');r(13,34,10,10,'#fff0ca');r(25,34,10,10,'#f4dfb9');r(23,33,2,13,'#947451');r(15,36,6,1,'#ab9471');r(15,39,6,1,'#ab9471');r(27,36,6,1,'#ab9471');r(27,39,6,1,'#ab9471');r(8,38,5,5,skin);r(35,38,5,5,light);save('learning','Learning · lectura y aprendizaje');
human('#76a96b','#48775a','#614a35');r(11,5,24,9,ink);r(13,5,20,8,'#d9bc58');r(21,4,5,9,'#fae19b');r(7,12,34,4,ink);r(9,12,30,2,'#f4d781');r(18,29,3,14,'#d9bc58');r(29,29,3,14,'#d9bc58');r(17,39,17,4,'#bd8c4f');r(38,29,3,19,'#87583b');box(33,26,12,7,'#bcc7c3');r(33,25,4,4,'#bcc7c3');save('factory','Factory · constructor y martillo');
robot('#f5d875','#656451');box(30,30,15,18,'#e3bb5a');r(33,33,9,9,'#ffdf85');r(37,35,2,5,'#fff1bf');r(35,37,6,2,'#fff1bf');r(32,47,11,2,ink);save('guardian','Guardian · robot protector');
human('#c5649a','#97496f','#62454f');r(31,10,8,21,'#62454f');r(35,26,6,7,'#ad7691');headset('#ec9fca');r(15,30,3,13,'#f0afd0');r(29,30,3,13,'#f0afd0');save('publisher','Publisher · comunicadora con auriculares');
robot('#83e0d8','#347a88');r(10,12,26,2,'#a7ece3');r(40,29,3,22,'#adbfc5');r(36,25,10,4,ink);r(35,20,4,8,'#adbfc5');r(43,20,4,8,'#d7e3dc');r(38,25,7,3,'#d7e3dc');r(40,46,3,3,'#eff5dd');save('recovery','Recovery · robot mecánico con llave inglesa');
robot('#8bd8ff','#2f63ae');r(10,10,29,4,'#f7f4df');r(13,12,4,2,'#b9e9ee');r(17,32,15,3,'#4d8ce2');r(22,35,5,5,'#9be6ff');r(4,21,4,6,'#498fe6');r(41,21,4,6,'#498fe6');save('astra','Astra · robot coordinador blanco y azul');
box(6,34,33,14,'#d6a276');r(10,32,20,6,'#efc796');r(8,29,5,8,'#b78569');r(20,29,5,8,'#b78569');r(8,33,18,10,'#efc796');r(10,37,4,1,ink);r(18,37,4,1,ink);r(14,40,3,1,'#b78569');r(32,36,9,9,'#efc796');r(37,42,6,5,'#efc796');r(28,44,12,3,'#efc796');save('cat','Gato dormido de Guardian');
