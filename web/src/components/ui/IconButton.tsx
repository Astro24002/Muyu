import type { ButtonHTMLAttributes, ReactElement, ReactNode } from 'react';

export interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'aria-label' | 'children' | 'title'> {
  label: string;
  icon: ReactNode;
}

export function IconButton({ label, icon, type = 'button', className, ...props }: IconButtonProps): ReactElement {
  return (
    <button
      {...props}
      type={type}
      aria-label={label}
      title={label}
      className={['ui-icon-button', className].filter(Boolean).join(' ')}
    >
      <span className="ui-icon-button__icon" aria-hidden="true">
        {icon}
      </span>
    </button>
  );
}
