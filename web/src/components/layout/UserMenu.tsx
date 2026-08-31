import { UserRound } from 'lucide-react';
import { useEffect, useRef, useState, type JSX } from 'react';
import { IconButton } from '../ui/IconButton';

export interface UserMenuProps {
  onLogout?: () => void;
}

export function UserMenu({ onLogout = () => undefined }: UserMenuProps): JSX.Element {
  const [open, setOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return undefined;

    const closeOnOutsideClick = (event: MouseEvent): void => {
      if (event.target instanceof Node && !menuRef.current?.contains(event.target)) setOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') setOpen(false);
    };
    document.addEventListener('mousedown', closeOnOutsideClick);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('mousedown', closeOnOutsideClick);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [open]);

  const logout = (): void => {
    setOpen(false);
    onLogout();
  };

  return (
    <div className="user-menu" ref={menuRef}>
      <IconButton
        label="用户菜单"
        icon={<UserRound aria-hidden="true" size={18} strokeWidth={1.8} />}
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen((value) => !value)}
      />
      {open ? (
        <div className="user-menu__popover" role="menu" aria-label="用户菜单">
          <p className="user-menu__label">当前用户</p>
          <button type="button" className="user-menu__item" onClick={logout}>
            退出登录
          </button>
        </div>
      ) : null}
    </div>
  );
}
