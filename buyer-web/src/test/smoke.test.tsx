import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import Home from '../app/page';

describe('Buyer Web Smoke Test', () => {
  it('renders the initial foundation page correctly', () => {
    render(<Home />);
    const heading = screen.getByText(/hello world/i);
    expect(heading).toBeInTheDocument();
  });
});
