import type { ButtonHTMLAttributes, ReactElement } from 'react';

export type ButtonTone = 'primary' | 'neutral' | 'quiet' | 'danger';

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  tone?: ButtonTone;
}

export function Button({ tone = 'primary', type = 'button', className, ...props }: ButtonProps): ReactElement {
  return (
    <button
      {...props}
      type={type}
      className={['ui-button', `ui-button--${tone}`, className].filter(Boolean).join(' ')}
    />
  );
}
