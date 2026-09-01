import type { HTMLAttributes, ReactElement } from 'react';

type HeadingTag = 'h2' | 'h3' | 'h4';

export interface SectionHeadingProps extends HTMLAttributes<HTMLHeadingElement> {
  level?: 2 | 3 | 4;
}

export function SectionHeading({ level = 2, className, ...props }: SectionHeadingProps): ReactElement {
  const Heading = `h${level}` as HeadingTag;

  return <Heading {...props} className={['ui-section-heading', className].filter(Boolean).join(' ')} />;
}
