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
    expect(screen.getByLabelText(/Order Number/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Receipt Access Key/i)).toBeInTheDocument();
  });

  it('displays validation error if submitted without order id or token', () => {
    render(<OrderLookupPage />);
    const submitBtn = screen.getByRole('button', { name: /Retrieve Order Receipt/i });
    
    fireEvent.click(submitBtn);
    expect(screen.getByText(/Please enter your order number or tracking link/i)).toBeInTheDocument();
    expect(mockPush).not.toHaveBeenCalled();

    const idInput = screen.getByLabelText(/Order Number/i);
    fireEvent.change(idInput, { target: { value: 'ord-123' } });
    fireEvent.click(submitBtn);
    expect(screen.getByText(/Please enter your receipt access key/i)).toBeInTheDocument();
    expect(mockPush).not.toHaveBeenCalled();
  });

  it('routes to order receipt on valid form submission', () => {
    render(<OrderLookupPage />);
    const idInput = screen.getByLabelText(/Order Number/i);
    const tokenInput = screen.getByLabelText(/Receipt Access Key/i);
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

  it('routes directly when buyer pastes a full tracking URL with token', () => {
    render(<OrderLookupPage />);
    const idInput = screen.getByLabelText(/Order Number/i);
    const submitBtn = screen.getByRole('button', { name: /Retrieve Order Receipt/i });

    fireEvent.change(idInput, {
      target: { value: 'https://livedrop.store/order/ord-link-555?token=link-token-xyz' },
    });
    fireEvent.click(submitBtn);

    expect(mockPush).toHaveBeenCalledWith('/order/ord-link-555?token=link-token-xyz');
  });

  it('routes automatically with cached token when buyer enters an order code saved on device', () => {
    window.localStorage.setItem('livedrop_order_token_ord-device-777', 'device-tok-999');
    render(<OrderLookupPage />);
    const idInput = screen.getByLabelText(/Order Number/i);
    const submitBtn = screen.getByRole('button', { name: /Retrieve Order Receipt/i });

    fireEvent.change(idInput, { target: { value: 'ord-device-777' } });
    fireEvent.click(submitBtn);

    expect(mockPush).toHaveBeenCalledWith('/order/ord-device-777?token=device-tok-999');
  });
});

