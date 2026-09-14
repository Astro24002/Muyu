import { ArrowRight, ChevronRight, Circle, MoreHorizontal } from 'lucide-react';
import type { JSX } from 'react';

type Quadrant = {
  code: string;
  name: string;
  tone: 'q1' | 'q2' | 'q3' | 'q4';
  tasks: string[];
};

const quadrants: Quadrant[] = [
  { code: 'Q1', name: '重要且紧急', tone: 'q1', tasks: ['完成生产发布检查', '修复登录失败问题', '确认周末采购清单', '补充接口文档', '第五项任务'] },
  { code: 'Q2', name: '重要不紧急', tone: 'q2', tasks: ['整理季度计划', '准备旅行物品'] },
  { code: 'Q3', name: '紧急不重要', tone: 'q3', tasks: ['回复待处理消息'] },
  { code: 'Q4', name: '不重要不紧急', tone: 'q4', tasks: [] },
];

export function QuadrantPreviewPage(): JSX.Element {
  return (
    <main className="quadrant-preview-page">
      <header className="quadrant-preview-page__intro">
        <p className="quadrant-preview-page__eyebrow">Muyu · Android 四象限</p>
        <h1>任务显示的三种方案</h1>
        <p>当前问题是宫格里编号抢占了任务标题。以下方案都以标题为主，只调整信息密度与浏览路径。</p>
      </header>
      <div className="quadrant-preview-page__options">
        <PreviewFrame label="方案 A" title="紧凑四格" description="保留当前 2×2 结构，标题优先，适合快速扫视。">
          <QuadrantGrid />
        </PreviewFrame>
        <PreviewFrame label="方案 B" title="纵向分组" description="按 Q1 到 Q4 纵向排列，任务标题有更多横向空间。">
          <QuadrantList />
        </PreviewFrame>
        <PreviewFrame label="方案 C" title="重点摘要" description="每格只突出第一项任务，其余任务收拢为数量入口。">
          <QuadrantFocus />
        </PreviewFrame>
      </div>
    </main>
  );
}

function PreviewFrame({ label, title, description, children }: { label: string; title: string; description: string; children: JSX.Element }): JSX.Element {
  return <section className="quadrant-preview-option"><div className="quadrant-preview-option__heading"><span>{label}</span><h2>{title}</h2></div><p className="quadrant-preview-option__description">{description}</p>{children}</section>;
}

function QuadrantGrid(): JSX.Element {
  return <div className="quadrant-demo quadrant-demo--grid">{quadrants.map((quadrant) => <QuadrantPanel key={quadrant.code} quadrant={quadrant} limit={4} more />)}</div>;
}

function QuadrantList(): JSX.Element {
  return <div className="quadrant-demo quadrant-demo--list">{quadrants.map((quadrant) => <QuadrantPanel key={quadrant.code} quadrant={quadrant} limit={3} more />)}</div>;
}

function QuadrantFocus(): JSX.Element {
  return <div className="quadrant-demo quadrant-demo--focus">{quadrants.map((quadrant) => <article className={`quadrant-focus-card quadrant-focus-card--${quadrant.tone}`} key={quadrant.code}><div className="quadrant-demo__heading"><span><b>{quadrant.code}</b>{quadrant.name}</span><strong>{quadrant.tasks.length}</strong></div>{quadrant.tasks.length === 0 ? <p className="quadrant-demo__empty">暂无任务</p> : <><button className="quadrant-focus-card__task" type="button"><Circle size={14} />{quadrant.tasks[0]}<ChevronRight size={15} /></button>{quadrant.tasks.length > 1 && <button className="quadrant-focus-card__more" type="button">查看其余 {quadrant.tasks.length - 1} 项 <ArrowRight size={14} /></button>}</>}</article>)}</div>;
}

function QuadrantPanel({ quadrant, limit, more = false }: { quadrant: Quadrant; limit: number; more?: boolean }): JSX.Element {
  const visible = quadrant.tasks.slice(0, limit);
  return <article className={`quadrant-panel quadrant-panel--${quadrant.tone}`}><div className="quadrant-demo__heading"><span><b>{quadrant.code}</b>{quadrant.name}</span><strong>{quadrant.tasks.length}</strong></div>{visible.length === 0 ? <p className="quadrant-demo__empty">暂无任务</p> : <div className="quadrant-panel__tasks">{visible.map((task) => <button className="quadrant-panel__task" type="button" key={task}><Circle size={13} /> <span>{task}</span><ChevronRight size={14} /></button>)}{more && quadrant.tasks.length > limit && <button className="quadrant-panel__more" type="button"><MoreHorizontal size={14} />更多任务</button>}</div>}</article>;
}
