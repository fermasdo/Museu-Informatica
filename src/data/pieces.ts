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
  imagePublicUrl?: string;
  imageCreditUrl?: string;
  imageCreditText?: string;
  imageLicenseUrl?: string;
  imageLicenseText?: string;
  isReferenceImage?: boolean;
  owner: string;
  tags: string[];
};

export const pieces: Piece[] = [
  { name: 'Olivetti Programma 101', year: 1965, decade: '1960', type: 'Ordinador', location: 'Corredor A', note: 'La programació de sobretaula abans del xip.', mark: 'MUS-000101', image: 'images/catalogue/computer.svg', imageAlt: 'Il·lustració d’un ordinador retro amb pantalla verda', owner: 'Museu', tags: ['basic', 'programacio', 'aula'] },
  { name: 'Sinclair ZX Spectrum', year: 1982, decade: '1980', type: 'Ordinador', location: 'Corredor A', note: 'Color, goma i una generació que va aprendre BASIC.', mark: 'MUS-000102', image: 'images/catalogue/computer.svg', imageAlt: 'Fotografia d’un ordinador Sinclair ZX Spectrum de 48 KB, vist des de davant', imagePublicUrl: 'https://commons.wikimedia.org/wiki/Special:FilePath/ZXSpectrum48k.jpg?width=960', imageCreditUrl: 'https://commons.wikimedia.org/wiki/File:ZXSpectrum48k.jpg', imageCreditText: 'Bill Bertram, sota llicència CC BY-SA 2.5, via Wikimedia Commons', imageLicenseUrl: 'https://creativecommons.org/licenses/by-sa/2.5/', imageLicenseText: 'CC BY-SA 2.5', isReferenceImage: true, owner: 'Donació', tags: ['basic', 'programacio', 'videojocs'] },
  { name: 'Commodore 64', year: 1982, decade: '1980', type: 'Ordinador', location: 'Corredor B', note: '64 KB que encara sonen a SID.', mark: 'MUS-000103', image: 'images/catalogue/computer.svg', imageAlt: 'Fotografia d’un ordinador Commodore 64 amb teclat integrat', imagePublicUrl: 'https://commons.wikimedia.org/wiki/Special:FilePath/Commodore-64-Computer-BL.jpg?width=960', imageCreditUrl: 'https://commons.wikimedia.org/wiki/File:Commodore-64-Computer-BL.jpg', imageCreditText: 'Evan-Amos, domini públic, via Wikimedia Commons', imageLicenseUrl: 'https://creativecommons.org/publicdomain/mark/1.0/', imageLicenseText: 'Domini públic (Public Domain Mark 1.0)', isReferenceImage: true, owner: 'Museu', tags: ['basic', 'videojocs', 'aula'] },
  { name: 'Game Boy', year: 1989, decade: '1980', type: 'Consola', location: 'Corredor B', note: 'El joc ix a passejar en escala de grisos.', mark: 'MUS-000104', image: 'images/catalogue/console.svg', imageAlt: 'Fotografia d’una consola portàtil Nintendo Game Boy original', imagePublicUrl: 'https://commons.wikimedia.org/wiki/Special:FilePath/Game-Boy-FL.jpg?width=960', imageCreditUrl: 'https://commons.wikimedia.org/wiki/File:Game-Boy-FL.jpg', imageCreditText: 'Evan-Amos, domini públic, via Wikimedia Commons', imageLicenseUrl: 'https://creativecommons.org/publicdomain/mark/1.0/', imageLicenseText: 'Domini públic (Public Domain Mark 1.0)', isReferenceImage: true, owner: 'Préstec', tags: ['videojocs', 'portatil'] },
  { name: 'Ratolí Apple', year: 1984, decade: '1980', type: 'Perifèric', location: 'Biblioteca', note: 'Una sola tecla per canviar la manera d’assenyalar.', mark: 'MUS-000105', image: 'images/catalogue/peripheral.svg', imageAlt: 'Il·lustració d’un ratolí d’ordinador', owner: 'Museu', tags: ['interficie-grafica', 'aula'] },
  { name: 'MS-DOS 5.0', year: 1991, decade: '1990', type: 'Documentació', location: 'Biblioteca', note: 'Manual d’un món que arrancava amb C:\\>.', mark: 'MUS-000106', image: 'images/catalogue/computer.svg', imageAlt: 'Il·lustració d’un terminal retro', owner: 'Donació', tags: ['manuals', 'programacio'] },
  { name: 'iMac G3', year: 1998, decade: '1990', type: 'Ordinador', location: 'Corredor A', note: 'Transparència, xarxa i color mandarina.', mark: 'MUS-000107', image: 'images/catalogue/computer.svg', imageAlt: 'Il·lustració d’un ordinador retro amb pantalla verda', owner: 'Museu', tags: ['interficie-grafica', 'aula'] },
  { name: 'Nokia 3310', year: 2000, decade: '2000', type: 'Perifèric', location: 'Corredor B', note: 'Un objecte quotidià que va canviar la conversa.', mark: 'MUS-000108', image: 'images/catalogue/peripheral.svg', imageAlt: 'Il·lustració d’un perifèric retro', owner: 'Donació', tags: ['telefonia', 'portatil'] }
];
