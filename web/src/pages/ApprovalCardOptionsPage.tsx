import { ArrowRight, Check, Clock3, UserRound, X } from 'lucide-react';
import type { JSX } from 'react';

const changes = [
  { label: '分类名称', from: '无', to: '测试分类' },
];

export function ApprovalCardOptionsPage(): JSX.Element {
  return (
    <main className="approval-options-page">
      <header className="approval-options-page__intro">
        <p className="approval-options-page__eyebrow">Muyu · Android 审批卡片</p>
        <h1>审批详情的三种展示方案</h1>
        <p>四个信息元素保持一致，只调整信息密度、阅读顺序和变更内容的强调方式。</p>
      </header>

      <div className="approval-options-page__grid">
        <OptionFrame number="方案 A" title="清晰分层" description="适合首次查看，四个元素按阅读顺序纵向展开。">
          <div className="approval-option-card approval-option-card--a">
            <div className="approval-option-card__b-top approval-option-card__a-subject">
              <span className="approval-option-card__index approval-option-card__a-subject-label">审批事项</span>
              <span className="approval-option-card__status">待审批</span>
            </div>
            <MetaLine />
            <InfoBlock label="审批类别">新建分类</InfoBlock>
            <ChangeBlock />
            <Actions />
          </div>
        </OptionFrame>

        <OptionFrame number="方案 B" title="紧凑双列" description="适合审批列表，元信息和审批类别并排，卡片更短。">
          <div className="approval-option-card approval-option-card--b">
            <div className="approval-option-card__b-top">
              <div><span className="approval-option-card__index">审批事项</span><h2>新建分类 - 测试分类</h2></div>
              <span className="approval-option-card__status">待审批</span>
            </div>
            <div className="approval-option-card__b-meta"><MetaLine compact /><span className="approval-option-card__category">审批类别　新建分类</span></div>
            <ChangeBlock compact />
            <Actions compact />
          </div>
        </OptionFrame>

        <OptionFrame number="方案 C" title="变更优先" description="适合快速判断，原内容和新内容成为卡片视觉中心。">
          <div className="approval-option-card approval-option-card--c">
            <div className="approval-option-card__c-heading"><span className="approval-option-card__category">新建分类</span><span className="approval-option-card__status">待审批</span></div>
            <span className="approval-option-card__index">审批事项</span>
            <h2>新建分类 - 测试分类</h2>
            <div className="approval-option-card__person-line"><span className="approval-option-card__avatar">溪</span><strong>溪岸</strong><span>发起</span><span className="approval-option-card__dot">·</span><Clock3 size={13} /><span>今天 12:32</span></div>
            <div className="approval-option-card__diff-list"><p className="approval-option-card__diff-title">变更内容</p>{changes.map((change) => <div className="approval-option-card__diff" key={change.label}><span>{change.label}</span><div><del>{change.from}</del><ArrowRight size={14} /><strong>{change.to}</strong></div></div>)}</div>
            <Actions compact />
          </div>
        </OptionFrame>
      </div>
    </main>
  );
}

function OptionFrame({ number, title, description, children }: { number: string; title: string; description: string; children: JSX.Element }): JSX.Element {
  return <section className="approval-options-page__option"><div className="approval-options-page__option-heading"><span>{number}</span><h2>{title}</h2></div><p>{description}</p>{children}</section>;
}

function OptionHeader({ category, status, label = '审批类别' }: { category: string; status: string; label?: string }): JSX.Element {
  return <div className="approval-option-card__header"><span className="approval-option-card__category">{label}　{category}</span><span className="approval-option-card__status">{status}</span></div>;
}

function MetaLine({ compact = false }: { compact?: boolean }): JSX.Element {
  return <div className={['approval-option-card__meta', compact ? 'approval-option-card__meta--compact' : ''].join(' ')}><span className="approval-option-card__avatar">溪</span><span><strong>溪岸</strong> 发起</span><span className="approval-option-card__dot">·</span><Clock3 size={13} /><span>2026年09月09日 12:32</span></div>;
}

function InfoBlock({ label, children }: { label: string; children: string }): JSX.Element {
  return <div className="approval-option-card__info"><span>{label}</span><strong>{children}</strong></div>;
}

function ChangeBlock({ compact = false }: { compact?: boolean }): JSX.Element {
  return <div className={['approval-option-card__changes', compact ? 'approval-option-card__changes--compact' : ''].join(' ')}><span>变更内容</span><div>{changes.map((change) => <p key={change.label}><b>{change.label}</b><span><del>{change.from}</del><ArrowRight size={14} /><strong>{change.to}</strong></span></p>)}</div></div>;
}

function Actions({ compact = false }: { compact?: boolean }): JSX.Element {
  return <div className={['approval-option-card__actions', compact ? 'approval-option-card__actions--compact' : ''].join(' ')}><button className="approval-option-card__approve" type="button"><Check size={15} />批准</button><button className="approval-option-card__reject" type="button"><X size={15} />拒绝</button></div>;
}
