import { Plus, Search, X } from 'lucide-react';
import { useEffect, useRef, useState, type FormEvent, type JSX } from 'react';
import type { Route } from '../../app/routes';
import type { WebSessionApi } from '../account/web-session-api';
import { IconButton } from '../ui/IconButton';
import { UserMenu } from './UserMenu';

export type PrimaryRoute = Extract<Route, { kind: 'matters' | 'ledger' | 'checkins' | 'me' }>;

export interface TopNavProps {
  route: Route;
  onNavigate: (route: PrimaryRoute) => void;
  onLogout?: () => void;
  onCreateTask?: () => void;
  onSearch?: (query: string) => void;
  sessionApi?: WebSessionApi;
  onAuthRequired?: () => void;
  pendingApprovalCount?: number;
}

const PRIMARY_NAV: Array<{ route: PrimaryRoute; label: string }> = [
  { route: { kind: 'matters', view: 'moment' }, label: '事项' },
  { route: { kind: 'ledger' }, label: '记账' },
  { route: { kind: 'checkins' }, label: '打卡' },
  { route: { kind: 'me' }, label: '我的' },
];

export function TopNav({
  route,
  onNavigate,
  onLogout,
  onCreateTask,
  onSearch,
  sessionApi,
  onAuthRequired,
  pendingApprovalCount = 0,
}: TopNavProps): JSX.Element {
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState('');
  const searchInputRef = useRef<HTMLInputElement>(null);
  const searchTriggerRef = useRef<HTMLButtonElement>(null);
  const searchWasOpenRef = useRef(false);

  useEffect(() => {
    if (searchOpen) {
      searchWasOpenRef.current = true;
      searchInputRef.current?.focus();
      return;
    }
    if (searchWasOpenRef.current) {
      searchWasOpenRef.current = false;
      if (searchTriggerRef.current?.isConnected) searchTriggerRef.current.focus();
    }
  }, [searchOpen]);

  useEffect(() => {
    if (!searchOpen) return undefined;
    const closeOnEscape = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') closeSearch();
    };
    document.addEventListener('keydown', closeOnEscape);
    return () => document.removeEventListener('keydown', closeOnEscape);
  }, [searchOpen]);

  const submitSearch = (event: FormEvent<HTMLFormElement>): void => {
    event.preventDefault();
    onSearch?.(query.trim());
  };

  const closeSearch = (): void => {
    setSearchOpen(false);
    setQuery('');
  };

  return (
    <header className="top-nav">
      <div className="top-nav__inner">
        <a
          className="top-nav__brand"
          href="#/matters"
          aria-label="木鱼，回到事项"
          onClick={(event) => {
            event.preventDefault();
            onNavigate({ kind: 'matters', view: 'moment' });
          }}
        >
          <span className="top-nav__brand-name">木鱼</span>
          <span className="top-nav__brand-mark">MUYU</span>
        </a>

        <nav className="top-nav__links" aria-label="主导航">
          {PRIMARY_NAV.map(({ route: targetRoute, label }) => {
            const active = isActiveRoute(route, targetRoute.kind);
            return (
              <a
                key={targetRoute.kind}
                className={['top-nav__link', active ? 'top-nav__link--active' : undefined].filter(Boolean).join(' ')}
                href={targetRoute.kind === 'matters' ? '#/matters' : `#/${targetRoute.kind}`}
                aria-current={active ? 'page' : undefined}
                data-active-indicator={active ? 'true' : undefined}
                onClick={(event) => {
                  event.preventDefault();
                  onNavigate(targetRoute);
                }}
              >
                <span>{label}</span>
              </a>
            );
          })}
        </nav>

        <div className="top-nav__actions">
          <IconButton
            ref={searchTriggerRef}
            label="搜索"
            icon={<Search aria-hidden="true" size={18} strokeWidth={1.8} />}
            aria-expanded={searchOpen}
            aria-controls="muyu-search-dialog"
            onClick={() => {
              if (searchOpen) closeSearch();
              else setSearchOpen(true);
            }}
          />
          {onCreateTask ? (
            <IconButton
              label="新建任务"
              icon={<Plus aria-hidden="true" size={19} strokeWidth={1.8} />}
              onClick={onCreateTask}
            />
          ) : null}
          <UserMenu onLogout={onLogout} sessionApi={sessionApi} onAuthRequired={onAuthRequired} />
        </div>

        {searchOpen ? (
          <div id="muyu-search-dialog" className="top-nav__search" role="dialog" aria-label="搜索" aria-modal="true">
            <form onSubmit={submitSearch}>
              <label htmlFor="muyu-search-input">搜索任务</label>
              <div className="top-nav__search-row">
                <input
                  ref={searchInputRef}
                  id="muyu-search-input"
                  type="search"
                  value={query}
                  placeholder="搜索任务"
                  autoComplete="off"
                  onChange={(event) => setQuery(event.target.value)}
                />
                <IconButton
                  label="关闭搜索"
                  icon={<X aria-hidden="true" size={18} strokeWidth={1.8} />}
                  onClick={closeSearch}
                />
              </div>
            </form>
            {query.trim() ? <p className="top-nav__search-query" aria-live="polite">{query.trim()}</p> : null}
          </div>
        ) : null}
      </div>
    </header>
  );
}

function isActiveRoute(route: Route, target: PrimaryRoute['kind']): boolean {
  return route.kind === target
    || (target === 'matters' && (route.kind === 'task' || route.kind === 'all-tasks' || route.kind === 'today' || route.kind === 'tasks'))
    || (target === 'me' && (route.kind === 'approvals' || route.kind === 'activity'));
}
