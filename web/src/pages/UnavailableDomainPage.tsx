import type { JSX } from 'react';

export function UnavailableDomainPage({ title }: { title: string }): JSX.Element {
  return <main className="domain-unavailable" data-domain-unavailable><h1>{title}</h1></main>;
}
