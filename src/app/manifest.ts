import type { MetadataRoute } from 'next';
export default function manifest(): MetadataRoute.Manifest {return {name:'SVIFMS Al-Ghalbi',short_name:'SVIFMS',start_url:'/',display:'standalone',background_color:'#f0f4f8',theme_color:'#082a45',icons:[{src:'/icon.svg',sizes:'any',type:'image/svg+xml',purpose:'any'}]};}
