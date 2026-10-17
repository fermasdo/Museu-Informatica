export type Piece = {
  name: string;
  year: number;
  decade: string;
  type: 'Ordinador' | 'Consola' | 'Perifèric' | 'Documentació';
  location: 'Corredor A' | 'Corredor B' | 'Biblioteca';
  note: string;
  mark: string;
};

export const pieces: Piece[] = [
  { name: 'Olivetti Programma 101', year: 1965, decade: '1960', type: 'Ordinador', location: 'Corredor A', note: 'La programació de sobretaula abans del xip.', mark: '101' },
  { name: 'Sinclair ZX Spectrum', year: 1982, decade: '1980', type: 'Ordinador', location: 'Corredor A', note: 'Color, goma i una generació que va aprendre BASIC.', mark: 'ZX' },
  { name: 'Commodore 64', year: 1982, decade: '1980', type: 'Ordinador', location: 'Corredor B', note: '64 KB que encara sonen a SID.', mark: 'C=' },
  { name: 'Game Boy', year: 1989, decade: '1980', type: 'Consola', location: 'Corredor B', note: 'El joc ix a passejar en escala de grisos.', mark: 'GB' },
  { name: 'Ratolí Apple', year: 1984, decade: '1980', type: 'Perifèric', location: 'Biblioteca', note: 'Una sola tecla per canviar la manera d’assenyalar.', mark: '⌁' },
  { name: 'MS-DOS 5.0', year: 1991, decade: '1990', type: 'Documentació', location: 'Biblioteca', note: 'Manual d’un món que arrancava amb C:\\>.', mark: 'DOS' },
  { name: 'iMac G3', year: 1998, decade: '1990', type: 'Ordinador', location: 'Corredor A', note: 'Transparència, xarxa i color mandarina.', mark: 'G3' },
  { name: 'Nokia 3310', year: 2000, decade: '2000', type: 'Perifèric', location: 'Corredor B', note: 'Un objecte quotidià que va canviar la conversa.', mark: '3310' }
];
