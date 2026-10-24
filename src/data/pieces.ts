export type Piece = {
  name: string;
  year: number;
  decade: string;
  type: 'Ordinador' | 'Consola' | 'Perifèric' | 'Documentació';
  location: 'Corredor A' | 'Corredor B' | 'Biblioteca';
  note: string;
  mark: string;
  image: string;
  imageAlt: string;
  owner: string;
};

export const pieces: Piece[] = [
  { name: 'Olivetti Programma 101', year: 1965, decade: '1960', type: 'Ordinador', location: 'Corredor A', note: 'La programació de sobretaula abans del xip.', mark: 'MUS-000101', image: 'images/catalogue/computer.svg', imageAlt: 'Il·lustració d’un ordinador retro amb pantalla verda', owner: 'Museu' },
  { name: 'Sinclair ZX Spectrum', year: 1982, decade: '1980', type: 'Ordinador', location: 'Corredor A', note: 'Color, goma i una generació que va aprendre BASIC.', mark: 'MUS-000102', image: 'images/catalogue/computer.svg', imageAlt: 'Il·lustració d’un ordinador retro amb pantalla verda', owner: 'Donació' },
  { name: 'Commodore 64', year: 1982, decade: '1980', type: 'Ordinador', location: 'Corredor B', note: '64 KB que encara sonen a SID.', mark: 'MUS-000103', image: 'images/catalogue/computer.svg', imageAlt: 'Il·lustració d’un ordinador retro amb pantalla verda', owner: 'Museu' },
  { name: 'Game Boy', year: 1989, decade: '1980', type: 'Consola', location: 'Corredor B', note: 'El joc ix a passejar en escala de grisos.', mark: 'MUS-000104', image: 'images/catalogue/console.svg', imageAlt: 'Il·lustració d’una consola portàtil retro', owner: 'Préstec' },
  { name: 'Ratolí Apple', year: 1984, decade: '1980', type: 'Perifèric', location: 'Biblioteca', note: 'Una sola tecla per canviar la manera d’assenyalar.', mark: 'MUS-000105', image: 'images/catalogue/peripheral.svg', imageAlt: 'Il·lustració d’un ratolí d’ordinador', owner: 'Museu' },
  { name: 'MS-DOS 5.0', year: 1991, decade: '1990', type: 'Documentació', location: 'Biblioteca', note: 'Manual d’un món que arrancava amb C:\\>.', mark: 'MUS-000106', image: 'images/catalogue/computer.svg', imageAlt: 'Il·lustració d’un terminal retro', owner: 'Donació' },
  { name: 'iMac G3', year: 1998, decade: '1990', type: 'Ordinador', location: 'Corredor A', note: 'Transparència, xarxa i color mandarina.', mark: 'MUS-000107', image: 'images/catalogue/computer.svg', imageAlt: 'Il·lustració d’un ordinador retro amb pantalla verda', owner: 'Museu' },
  { name: 'Nokia 3310', year: 2000, decade: '2000', type: 'Perifèric', location: 'Corredor B', note: 'Un objecte quotidià que va canviar la conversa.', mark: 'MUS-000108', image: 'images/catalogue/peripheral.svg', imageAlt: 'Il·lustració d’un perifèric retro', owner: 'Donació' }
];
