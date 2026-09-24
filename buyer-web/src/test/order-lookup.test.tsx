import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import OrderLookupPage from '../app/order/page';

const mockPush = vi.fn();

vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: mockPush,
    replace: vi.fn(),
  }),
  usePathname: () => '/order',
  useSearchParams: () => new URLSearchParams(),
}));

describe('Order Lookup Page (/order)', () => {
  beforeEach(() => {
    window.localStorage.clear();
    mockPush.mockClear();
  });

  it('renders order lookup page with heading and inputs', () => {
    render(<OrderLookupPage />);
    expect(screen.getByText('Track Your Order')).toBeInTheDocument();
    expect(screen.getByLabelText(/Order Identifier/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Order Security Token/i)).toBeInTheDocument();
  });

  it('displays validation error if submitted without order id or token', () => {
    render(<OrderLookupPage />);
    const submitBtn = screen.getByRole('button', { name: /Retrieve Order Receipt/i });
    
    fireEvent.click(submitBtn);
    expect(screen.getByText('Please enter your Order ID')).toBeInTheDocument();
    expect(mockPush).not.toHaveBeenCalled();

    const idInput = screen.getByLabelText(/Order Identifier/i);
    fireEvent.change(idInput, { target: { value: 'ord-123' } });
    fireEvent.click(submitBtn);
    expect(screen.getByText('Please enter your Order Access Token')).toBeInTheDocument();
    expect(mockPush).not.toHaveBeenCalled();
  });

  it('routes to order receipt on valid form submission', () => {
    render(<OrderLookupPage />);
    const idInput = screen.getByLabelText(/Order Identifier/i);
    const tokenInput = screen.getByLabelText(/Order Security Token/i);
    const submitBtn = screen.getByRole('button', { name: /Retrieve Order Receipt/i });

    fireEvent.change(idInput, { target: { value: 'ord-999' } });
    fireEvent.change(tokenInput, { target: { value: 'token-secret' } });
    fireEvent.click(submitBtn);

    expect(mockPush).toHaveBeenCalledWith('/order/ord-999?token=token-secret');
  });

  it('displays cached orders from localStorage if present', () => {
    window.localStorage.setItem('livedrop_order_token_ord-abc-123', 'tok-abc');
    render(<OrderLookupPage />);

    expect(screen.getByText('Recent Orders on This Device')).toBeInTheDocument();
    expect(screen.getByText(/Order #ord-abc-/i)).toBeInTheDocument();
  });
});
