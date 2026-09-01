import { Plus, Search, X } from 'lucide-react';
import { useEffect, useRef, useState, type FormEvent, type JSX } from 'react';
import type { Route } from '../../app/routes';
import type { WebSessionApi } from '../account/web-session-api';
import { IconButton } from '../ui/IconButton';
import { UserMenu } from './UserMenu';

export type PrimaryRoute = Extract<Route, { kind: 'today' | 'tasks' | 'approvals' | 'activity' }>;

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
  { route: { kind: 'today' }, label: '今天' },
  { route: { kind: 'tasks' }, label: '所有任务' },
  { route: { kind: 'approvals' }, label: '审批' },
  { route: { kind: 'activity' }, label: '动态' },
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
          href="#/today"
          aria-label="木鱼，回到今天"
          onClick={(event) => {
            event.preventDefault();
            onNavigate({ kind: 'today' });
          }}
        >
          <span className="top-nav__brand-name">木鱼</span>
          <span className="top-nav__brand-mark">MUYU</span>
        </a>

        <nav className="top-nav__links" aria-label="主导航">
          {PRIMARY_NAV.map(({ route: targetRoute, label }) => {
            const active = isActiveRoute(route, targetRoute.kind);
            const isApproval = targetRoute.kind === 'approvals';
            return (
              <a
                key={targetRoute.kind}
                className={['top-nav__link', active ? 'top-nav__link--active' : undefined].filter(Boolean).join(' ')}
                href={`#/${targetRoute.kind}`}
                aria-current={active ? 'page' : undefined}
                data-active-indicator={active ? 'true' : undefined}
                onClick={(event) => {
                  event.preventDefault();
                  onNavigate(targetRoute);
                }}
              >
                <span>{label}</span>
                {isApproval && pendingApprovalCount > 0 ? (
                  <span className="top-nav__badge" aria-label={`${pendingApprovalCount} 个待处理审批`}>
                    {pendingApprovalCount}
                  </span>
                ) : null}
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
          <IconButton
            label="新建任务"
            icon={<Plus aria-hidden="true" size={19} strokeWidth={1.8} />}
            onClick={onCreateTask}
          />
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
  return route.kind === target || (target === 'tasks' && route.kind === 'task');
}
