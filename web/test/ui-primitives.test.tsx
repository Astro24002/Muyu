import { describe, expect, it, vi } from 'vitest';
import { fireEvent, screen } from '@testing-library/react';
import { Button } from '../src/components/ui/Button';
import { IconButton } from '../src/components/ui/IconButton';
import { SectionHeading } from '../src/components/ui/SectionHeading';
import { StatusBadge } from '../src/components/ui/StatusBadge';
import { render } from './react-test-helpers';

describe('Button', () => {
  it('defaults to a non-submitting button and accepts an explicit submit type', () => {
    const { rerender } = render(<Button>Save</Button>);

    expect(screen.getByRole('button', { name: 'Save' })).toHaveAttribute('type', 'button');

    rerender(<Button type="submit">Save</Button>);

    expect(screen.getByRole('button', { name: 'Save' })).toHaveAttribute('type', 'submit');
  });

  it('does not invoke its click handler while disabled', () => {
    const onClick = vi.fn();
    render(
      <Button disabled onClick={onClick}>
        Save
      </Button>,
    );

    const button = screen.getByRole('button', { name: 'Save' });
    fireEvent.click(button);

    expect(button).toBeDisabled();
    expect(onClick).not.toHaveBeenCalled();
  });

  it('exposes the selected tone through its stable class contract', () => {
    render(<Button tone="danger">Delete</Button>);

    expect(screen.getByRole('button', { name: 'Delete' })).toHaveClass('ui-button', 'ui-button--danger');
  });
});

describe('IconButton', () => {
  it('uses its label for both the accessible name and the native tooltip', () => {
    render(<IconButton label="Open menu" icon={<span data-testid="menu-icon" />} />);

    const button = screen.getByRole('button', { name: 'Open menu' });
    expect(button).toHaveAttribute('aria-label', 'Open menu');
    expect(button).toHaveAttribute('title', 'Open menu');
    expect(button).toHaveClass('ui-icon-button');
    expect(screen.getByTestId('menu-icon')).toBeInTheDocument();
  });

  it('does not invoke its click handler while disabled', () => {
    const onClick = vi.fn();
    render(<IconButton label="Refresh" icon={<span />} disabled onClick={onClick} />);

    const button = screen.getByRole('button', { name: 'Refresh' });
    fireEvent.click(button);

    expect(button).toBeDisabled();
    expect(onClick).not.toHaveBeenCalled();
  });
});

describe('StatusBadge', () => {
  it('renders the status text and matching status class', () => {
    render(<StatusBadge status="waiting">Waiting</StatusBadge>);

    const badge = screen.getByText('Waiting');
    expect(badge).toHaveClass('ui-status-badge', 'ui-status-badge--waiting');
    expect(badge).toHaveAttribute('data-status', 'waiting');
  });

  it('uses the status as text when no label is provided', () => {
    render(<StatusBadge status="completed" />);

    expect(screen.getByText('completed')).toHaveClass('ui-status-badge--completed');
  });
});

describe('SectionHeading', () => {
  it('renders a labelled heading element that can be referenced by a section', () => {
    render(
      <SectionHeading id="next-heading" level={2}>
        Next
      </SectionHeading>,
    );

    const heading = screen.getByRole('heading', { name: 'Next', level: 2 });
    expect(heading).toHaveAttribute('id', 'next-heading');
    expect(heading).toHaveClass('ui-section-heading');
  });
});
