import { UserRound } from 'lucide-react';
import { useEffect, useRef, useState, type JSX } from 'react';
import type { WebSessionViewApi } from '../../ui/web-session-view';
import { WebSessionPanel } from '../account/WebSessionPanel';
import { IconButton } from '../ui/IconButton';

export interface UserMenuProps {
  onLogout?: () => void;
  sessionApi?: WebSessionViewApi;
  onAuthRequired?: () => void;
  now?: () => number;
}

export function UserMenu({ onLogout = () => undefined, sessionApi, onAuthRequired, now }: UserMenuProps): JSX.Element {
  const [open, setOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const popoverRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return undefined;

    popoverRef.current?.focus();

    const closeOnOutsideClick = (event: MouseEvent): void => {
      if (event.target instanceof Node && !menuRef.current?.contains(event.target)) closeMenu();
    };
    const closeOnEscape = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') closeMenu();
    };
    document.addEventListener('mousedown', closeOnOutsideClick);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('mousedown', closeOnOutsideClick);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [open]);

  const closeMenu = (): void => {
    setOpen(false);
    triggerRef.current?.focus();
  };

  const logout = (): void => {
    closeMenu();
    onLogout();
  };

  return (
    <div className="user-menu" ref={menuRef}>
      <IconButton
        ref={triggerRef}
        label="用户菜单"
        icon={<UserRound aria-hidden="true" size={18} strokeWidth={1.8} />}
        aria-expanded={open}
        aria-haspopup="dialog"
        aria-controls="muyu-user-menu-popover"
        onClick={() => {
          if (open) closeMenu();
          else setOpen(true);
        }}
      />
      {open ? (
        <div
          ref={popoverRef}
          id="muyu-user-menu-popover"
          className="user-menu__popover"
          role="dialog"
          aria-labelledby="muyu-user-menu-title"
          aria-modal="false"
          tabIndex={-1}
        >
          <p id="muyu-user-menu-title" className="user-menu__label">用户菜单</p>
          {sessionApi ? <WebSessionPanel api={sessionApi} onAuthRequired={onAuthRequired} now={now} /> : null}
          <button type="button" className="user-menu__item" onClick={logout}>
            退出登录
          </button>
        </div>
      ) : null}
    </div>
  );
}
