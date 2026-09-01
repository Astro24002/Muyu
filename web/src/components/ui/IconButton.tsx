import { forwardRef, type ButtonHTMLAttributes, type ReactElement, type ReactNode } from 'react';

export interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'aria-label' | 'children' | 'title'> {
  label: string;
  icon: ReactNode;
}

export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { label, icon, type = 'button', className, ...props },
  ref,
): ReactElement {
  return (
    <button
      {...props}
      ref={ref}
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
});
